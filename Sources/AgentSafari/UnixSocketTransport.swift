import AgentSafariCore
import Darwin
import Foundation

func makeUnixAddress(path: String) throws -> sockaddr_un {
    var address = sockaddr_un()
    address.sun_family = sa_family_t(AF_UNIX)

    let pathBytes = Array(path.utf8)
    let capacity = MemoryLayout.size(ofValue: address.sun_path)
    guard pathBytes.count < capacity else {
        throw AgentSafariError.socketPathTooLong(path)
    }

    withUnsafeMutablePointer(to: &address.sun_path) { pointer in
        pointer.withMemoryRebound(to: CChar.self, capacity: capacity) { buffer in
            for index in 0..<capacity {
                buffer[index] = 0
            }
            for (index, byte) in pathBytes.enumerated() {
                buffer[index] = CChar(bitPattern: byte)
            }
        }
    }

    return address
}

func withSockaddr<T>(_ address: inout sockaddr_un, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) rethrows -> T {
    try withUnsafePointer(to: &address) { pointer in
        try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
            try body(sockaddrPointer, socklen_t(MemoryLayout<sockaddr_un>.size))
        }
    }
}

func lastErrnoMessage(_ operation: String) -> String {
    "\(operation) failed: \(String(cString: strerror(errno)))"
}

final class UnixSocketServer {
    private let path: String
    private let browser: BrowserController
    private var serverFD: Int32 = -1

    init(path: String, browser: BrowserController) {
        self.path = path
        self.browser = browser
    }

    func start() throws {
        try? FileManager.default.removeItem(atPath: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw AgentSafariError.socketOperationFailed(lastErrnoMessage("socket")) }
        serverFD = fd

        var address = try makeUnixAddress(path: path)
        let bindResult = withSockaddr(&address) { sockaddrPointer, length in
            Darwin.bind(fd, sockaddrPointer, length)
        }
        guard bindResult == 0 else {
            close(fd)
            throw AgentSafariError.socketOperationFailed(lastErrnoMessage("bind"))
        }

        guard listen(fd, SOMAXCONN) == 0 else {
            close(fd)
            throw AgentSafariError.socketOperationFailed(lastErrnoMessage("listen"))
        }

        DispatchQueue.global(qos: .userInitiated).async { [fd, browser] in
            while true {
                let clientFD = accept(fd, nil, nil)
                if clientFD >= 0 {
                    handleClient(fd: clientFD, browser: browser)
                }
            }
        }

        print("agent-safari daemon listening on unix://\(path)")
    }

    deinit {
        if serverFD >= 0 {
            close(serverFD)
        }
        try? FileManager.default.removeItem(atPath: path)
    }
}

func readLineFromFD(_ fd: Int32) -> Data? {
    var data = Data()
    var byte: UInt8 = 0

    while true {
        let count = Darwin.read(fd, &byte, 1)
        if count == 1 {
            if byte == 10 { return data }
            data.append(byte)
        } else if count == 0 {
            return data.isEmpty ? nil : data
        } else if errno == EINTR {
            continue
        } else {
            return nil
        }
    }
}

func writeAll(fd: Int32, data: Data) {
    data.withUnsafeBytes { rawBuffer in
        guard let baseAddress = rawBuffer.baseAddress else { return }
        var written = 0
        while written < data.count {
            let result = Darwin.write(fd, baseAddress.advanced(by: written), data.count - written)
            if result > 0 {
                written += result
            } else if errno == EINTR {
                continue
            } else {
                break
            }
        }
    }
}

func handleClient(fd: Int32, browser: BrowserController) {
    guard let data = readLineFromFD(fd) else {
        close(fd)
        return
    }

    Task { @MainActor in
        let response: RPCResponse
        do {
            let request = try JSONDecoder().decode(RPCRequest.self, from: data)
            response = await handle(request, browser: browser)
        } catch {
            response = RPCResponse(
                id: nil,
                ok: false,
                result: nil,
                error: RPCErrorPayload(code: "decode_error", message: error.localizedDescription)
            )
        }

        let encoded = (try? JSONEncoder().encode(response)) ?? Data()
        writeAll(fd: fd, data: encoded + Data([10]))
        close(fd)
    }
}

func connectClient(socketPath: String) throws -> Int32 {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw AgentSafariError.socketOperationFailed(lastErrnoMessage("socket")) }

    var address = try makeUnixAddress(path: socketPath)
    let connectResult = withSockaddr(&address) { sockaddrPointer, length in
        Darwin.connect(fd, sockaddrPointer, length)
    }
    guard connectResult == 0 else {
        close(fd)
        throw AgentSafariError.socketOperationFailed(lastErrnoMessage("connect"))
    }
    return fd
}

func sendClient(method: String, params: [String: String], socketPath: String) throws {
    let fd = try connectClient(socketPath: socketPath)
    defer { close(fd) }

    let request = RPCRequest(id: UUID().uuidString, method: method, params: params)
    var payload = try JSONEncoder().encode(request)
    payload.append(10)
    writeAll(fd: fd, data: payload)

    if let response = readLineFromFD(fd), let text = String(data: response, encoding: .utf8) {
        print(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

