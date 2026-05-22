import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    func screenshot(path: String) async throws -> [String: String] {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        let image = try await webView.takeSnapshot(configuration: configuration)
        let url = try writePNG(image, path: path)
        return [
            "path": url.path,
            "fullPage": "false",
            "width": String(Int(webView.bounds.width.rounded())),
            "height": String(Int(webView.bounds.height.rounded())),
            "strategy": "viewport"
        ]
    }

    func screenshotFull(path: String) async throws -> [String: String] {
        let pageSize = try await measurePageSize()
        let maxSingleSnapshotPixels: CGFloat = 16_000_000
        let pixelArea = pageSize.width * pageSize.height

        if pixelArea <= maxSingleSnapshotPixels {
            let configuration = WKSnapshotConfiguration()
            configuration.rect = NSRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
            let image = try await webView.takeSnapshot(configuration: configuration)
            let url = try writePNG(image, path: path)
            return [
                "path": url.path,
                "fullPage": "true",
                "width": String(Int(pageSize.width.rounded())),
                "height": String(Int(pageSize.height.rounded())),
                "strategy": "single-rect",
                "tiles": "1"
            ]
        }

        let url = try await writeTiledFullPageScreenshot(pageSize: pageSize, path: path)
        let tileCount = max(1, Int(ceil(pageSize.height / max(1, webView.bounds.height))))
        return [
            "path": url.path,
            "fullPage": "true",
            "width": String(Int(pageSize.width.rounded())),
            "height": String(Int(pageSize.height.rounded())),
            "strategy": "tiled-scroll",
            "tiles": String(tileCount)
        ]
    }

    private func writeTiledFullPageScreenshot(pageSize: CGSize, path: String) async throws -> URL {
        let viewport = webView.bounds.size
        let pageWidth = max(1, min(pageSize.width, viewport.width))
        let pageHeight = max(1, pageSize.height)
        let tileHeight = max(1, viewport.height)
        let tileCount = max(1, Int(ceil(pageHeight / tileHeight)))
        let originalScrollValue = try await webView.evaluateJavaScript("({ x: window.scrollX || 0, y: window.scrollY || 0 })")
        let originalScroll = originalScrollValue as? [String: Any]
        let originalX = CGFloat((originalScroll?["x"] as? NSNumber)?.doubleValue ?? 0)
        let originalY = CGFloat((originalScroll?["y"] as? NSNumber)?.doubleValue ?? 0)
        defer {
            Task { @MainActor in
                _ = try? await webView.evaluateJavaScript("window.scrollTo(\(Int(originalX.rounded())), \(Int(originalY.rounded())))")
            }
        }

        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(pageWidth.rounded(.up)),
            pixelsHigh: Int(pageHeight.rounded(.up)),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            throw AgentSafariError.screenshotFailed
        }

        NSGraphicsContext.saveGraphicsState()
        guard let context = NSGraphicsContext(bitmapImageRep: bitmap) else {
            NSGraphicsContext.restoreGraphicsState()
            throw AgentSafariError.screenshotFailed
        }
        NSGraphicsContext.current = context
        NSColor.white.setFill()
        NSRect(x: 0, y: 0, width: pageWidth, height: pageHeight).fill()

        for index in 0..<tileCount {
            let yOffset = min(CGFloat(index) * tileHeight, max(0, pageHeight - tileHeight))
            _ = try await webView.evaluateJavaScript("window.scrollTo(0, \(Int(yOffset.rounded())))")
            try await Task.sleep(nanoseconds: 120_000_000)

            let configuration = WKSnapshotConfiguration()
            configuration.rect = NSRect(x: 0, y: 0, width: pageWidth, height: min(tileHeight, pageHeight))
            let tile = try await webView.takeSnapshot(configuration: configuration)
            let remainingHeight = max(0, pageHeight - yOffset)
            let drawHeight = min(tileHeight, remainingHeight)
            let destination = NSRect(x: 0, y: max(0, pageHeight - yOffset - drawHeight), width: pageWidth, height: drawHeight)
            let source = NSRect(x: 0, y: tile.size.height - drawHeight, width: min(pageWidth, tile.size.width), height: drawHeight)
            tile.draw(in: destination, from: source, operation: .copy, fraction: 1.0)
        }

        NSGraphicsContext.current = nil
        NSGraphicsContext.restoreGraphicsState()

        guard let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AgentSafariError.screenshotFailed
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        return url
    }

    private func measurePageSize() async throws -> CGSize {
        let script = """
        (() => {
          const de = document.documentElement;
          const b = document.body;
          const width = Math.max(
            de ? de.scrollWidth : 0,
            de ? de.offsetWidth : 0,
            de ? de.clientWidth : 0,
            b ? b.scrollWidth : 0,
            b ? b.offsetWidth : 0,
            b ? b.clientWidth : 0,
            window.innerWidth || 0
          );
          const height = Math.max(
            de ? de.scrollHeight : 0,
            de ? de.offsetHeight : 0,
            de ? de.clientHeight : 0,
            b ? b.scrollHeight : 0,
            b ? b.offsetHeight : 0,
            b ? b.clientHeight : 0,
            window.innerHeight || 0
          );
          return { width, height };
        })()
        """
        let value = try await webView.evaluateJavaScript(script)
        guard let result = value as? [String: Any] else {
            throw AgentSafariError.pageMeasurementFailed
        }
        let width = CGFloat((result["width"] as? NSNumber)?.doubleValue ?? 0)
        let height = CGFloat((result["height"] as? NSNumber)?.doubleValue ?? 0)
        guard width > 0, height > 0 else {
            throw AgentSafariError.pageMeasurementFailed
        }
        return CGSize(width: width, height: height)
    }

    private func writePNG(_ image: NSImage, path: String) throws -> URL {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw AgentSafariError.screenshotFailed
        }
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
        return url
    }
}
