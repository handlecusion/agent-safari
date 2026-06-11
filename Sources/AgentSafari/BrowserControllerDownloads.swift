import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    static let downloadsRoot = "\(NSHomeDirectory())/.agent-safari/downloads"

    /// Registers a fresh download, sets it as this tab's download-started evidence so the
    /// triggering navigate()/click() can report it, and attaches `self` as the delegate.
    func beginDownload(_ download: WKDownload, originatingWebView: WKWebView?) {
        let downloadID = UUID().uuidString
        let sourceURL = download.originalRequest?.url?.absoluteString ?? ""
        let originTabID = originatingWebView.flatMap { tabID(for: $0) } ?? activeTabID
        let record = DownloadRecord(
            id: downloadID,
            url: sourceURL,
            suggestedFilename: "",
            path: "",
            tabId: originTabID
        )
        appendDownloadRecord(record)
        downloadRecordsByDownload[ObjectIdentifier(download)] = downloadID
        if let originatingWebView {
            setPendingDownloadStarted(downloadID, for: originatingWebView)
        }
        download.delegate = self
    }

    private func appendDownloadRecord(_ record: DownloadRecord) {
        downloadsModel.append(record)
        guard downloadsModel.count > downloadModelCap else { return }
        // Drop the oldest completed entry; if none are completed, drop the oldest entry.
        if let oldestCompletedIndex = downloadsModel.firstIndex(where: { $0.state == "completed" }) {
            downloadsModel.remove(at: oldestCompletedIndex)
        } else {
            downloadsModel.removeFirst()
        }
    }

    func recordForDownload(_ download: WKDownload) -> DownloadRecord? {
        guard let id = downloadRecordsByDownload[ObjectIdentifier(download)] else { return nil }
        return downloadsModel.first { $0.id == id }
    }

    func download(
        _ download: WKDownload,
        decideDestinationUsing response: URLResponse,
        suggestedFilename: String,
        completionHandler: @escaping @MainActor @Sendable (URL?) -> Void
    ) {
        let record = recordForDownload(download)
        let safeName = sanitizedFilename(suggestedFilename)
        let dirURL = URL(fileURLWithPath: BrowserController.downloadsRoot)
            .appendingPathComponent(record?.id ?? UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: dirURL, withIntermediateDirectories: true)
        } catch {
            fputs("[agent-safari] download destination dir failed: \(error.localizedDescription)\n", stderr)
            completionHandler(nil)
            return
        }
        let destination = dirURL.appendingPathComponent(safeName)
        record?.suggestedFilename = safeName
        record?.path = destination.path
        completionHandler(destination)
    }

    func downloadDidFinish(_ download: WKDownload) {
        if let record = recordForDownload(download) {
            record.state = "completed"
        }
        downloadRecordsByDownload.removeValue(forKey: ObjectIdentifier(download))
    }

    func download(_ download: WKDownload, didFailWithError error: Error, resumeData: Data?) {
        if let record = recordForDownload(download) {
            record.state = "failed"
            record.error = error.localizedDescription
        }
        downloadRecordsByDownload.removeValue(forKey: ObjectIdentifier(download))
    }

    private func sanitizedFilename(_ name: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? "download" : trimmed
        // Strip path separators so a hostile suggestedFilename cannot escape the dir.
        return base.replacingOccurrences(of: "/", with: "_").replacingOccurrences(of: "\\", with: "_")
    }

    func downloads() async throws -> [String: String] {
        let items = downloadsModel.map { record in
            JSONValue.object([
                "id": .string(record.id),
                "url": .string(record.url),
                "filename": .string(record.suggestedFilename),
                "path": .string(record.path),
                "state": .string(record.state),
                "error": .string(record.error ?? ""),
                "tabId": .string(record.tabId)
            ])
        }
        let encoded = try JSONEncoder().encode(items)
        return [
            "downloads": String(data: encoded, encoding: .utf8) ?? "[]",
            "count": String(downloadsModel.count)
        ]
    }

    /// Polls until the requested download leaves the pending state. `id` of `--last`
    /// resolves to the most recently started download. Times out with wait_timeout.
    func waitForDownload(id: String, timeoutMs: Int) async throws -> [String: String] {
        let clampedTimeoutMs = max(0, timeoutMs)
        let deadline = Date().addingTimeInterval(Double(clampedTimeoutMs) / 1000.0)
        repeat {
            guard let record = resolveDownload(id: id) else {
                throw AgentSafariError.unknownDownload(id)
            }
            if record.state != "pending" {
                return downloadResultFields(record, timeoutMs: clampedTimeoutMs)
            }
            if Date() >= deadline { break }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while true
        throw AgentSafariError.waitTimedOut(clampedTimeoutMs)
    }

    private func resolveDownload(id: String) -> DownloadRecord? {
        if id == "--last" || id == "last" {
            return downloadsModel.last
        }
        return downloadsModel.first { $0.id == id }
    }

    private func downloadResultFields(_ record: DownloadRecord, timeoutMs: Int) -> [String: String] {
        [
            "id": record.id,
            "url": record.url,
            "filename": record.suggestedFilename,
            "path": record.path,
            "state": record.state,
            "error": record.error ?? "",
            "downloadTabId": record.tabId,
            "timeoutMs": String(timeoutMs)
        ]
    }
}
