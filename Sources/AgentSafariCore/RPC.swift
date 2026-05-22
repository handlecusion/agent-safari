import Foundation

public enum JSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String)
    case array([JSONValue])
    case object([String: JSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Double.self) {
            self = .number(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([JSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: JSONValue].self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null:
            try container.encodeNil()
        case .bool(let value):
            try container.encode(value)
        case .number(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        case .array(let values):
            try container.encode(values)
        case .object(let values):
            try container.encode(values)
        }
    }

    public static func fromStringMap(_ values: [String: String]) -> JSONValue {
        .object(values.mapValues { value in
            if value == "true" { return .bool(true) }
            if value == "false" { return .bool(false) }
            if let intValue = Int(value), String(intValue) == value { return .number(Double(intValue)) }
            if let doubleValue = Double(value), value.contains(".") { return .number(doubleValue) }
            return .string(value)
        })
    }

    public static func parseJSONText(_ text: String) -> JSONValue {
        guard let data = text.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) else {
            return .string(text)
        }
        return fromJSONObject(object)
    }

    public static func fromJSONObject(_ object: Any) -> JSONValue {
        if object is NSNull { return .null }
        if let value = object as? Bool { return .bool(value) }
        if let value = object as? NSNumber {
            if CFGetTypeID(value) == CFBooleanGetTypeID() { return .bool(value.boolValue) }
            return .number(value.doubleValue)
        }
        if let value = object as? String { return .string(value) }
        if let values = object as? [Any] { return .array(values.map(fromJSONObject)) }
        if let values = object as? [String: Any] { return .object(values.mapValues(fromJSONObject)) }
        return .string(String(describing: object))
    }
}

public struct RPCRequest: Codable, Equatable, Sendable {
    public let id: String?
    public let method: String
    public let params: [String: String]?

    public init(id: String?, method: String, params: [String: String]?) {
        self.id = id
        self.method = method
        self.params = params
    }
}

public struct RPCResponse: Codable, Equatable, Sendable {
    public let id: String?
    public let ok: Bool
    public let result: JSONValue?
    public let error: RPCErrorPayload?

    public init(id: String?, ok: Bool, result: JSONValue?, error: RPCErrorPayload?) {
        self.id = id
        self.ok = ok
        self.result = result
        self.error = error
    }
}

public struct RPCErrorPayload: Codable, Equatable, Sendable {
    public let code: String
    public let message: String

    public init(code: String, message: String) {
        self.code = code
        self.message = message
    }
}
