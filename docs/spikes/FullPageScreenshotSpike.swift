import AppKit
import Foundation
import WebKit

/// Standalone spike only. Not part of Package.swift and not used by production code.
///
/// Purpose:
/// - validate the WKWebView APIs and Swift types needed for full-page PNG capture;
/// - keep the implementation sketch separate from Sources/AgentSafari/main.swift.
///
/// Proposed production shape:
///   BrowserController.screenshot(path:fullPage:) -> [String: String]
/// where fullPage=false keeps today's viewport behavior and fullPage=true calls
/// FullPageScreenshotRenderer.capturePNG(from:to:options:).
@MainActor
final class FullPageScreenshotRenderer {
    struct Options {
        var maxSingleSnapshotPixels: CGFloat = 16_000_000
        var maxTileHeight: CGFloat = 4096
        var delayAfterScrollNanoseconds: UInt64 = 150_000_000
    }

    struct PageSize {
        let width: CGFloat
        let height: CGFloat
    }

    enum CaptureError: Error {
        case invalidPageSize
        case imageEncodingFailed
        case cgImageUnavailable
    }

    func capturePNG(from webView: WKWebView, to path: String, options: Options = Options()) async throws {
        let pageSize = try await measuredPageSize(webView)
        let image: NSImage

        if pageSize.width * pageSize.height <= options.maxSingleSnapshotPixels {
            image = try await singleFullRectSnapshot(webView, pageSize: pageSize)
        } else {
            image = try await tiledScrollSnapshot(webView, pageSize: pageSize, options: options)
        }

        let png = try pngData(from: image)
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try png.write(to: url)
    }

    /// Measure with JavaScript, not only `scrollView.contentSize`, because pages can
    /// report larger content through body/documentElement scroll/offset/client sizes.
    private func measuredPageSize(_ webView: WKWebView) async throws -> PageSize {
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
        guard let dict = value as? [String: Any],
              let widthNumber = dict["width"] as? NSNumber,
              let heightNumber = dict["height"] as? NSNumber else {
            throw CaptureError.invalidPageSize
        }

        let width = CGFloat(truncating: widthNumber)
        let height = CGFloat(truncating: heightNumber)
        guard width > 0, height > 0 else { throw CaptureError.invalidPageSize }
        return PageSize(width: ceil(width), height: ceil(height))
    }

    /// Fast path: ask WebKit for one large rect. This is the least invasive path
    /// when it works, but should be guarded by a pixel budget and verified on long pages.
    private func singleFullRectSnapshot(_ webView: WKWebView, pageSize: PageSize) async throws -> NSImage {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = CGRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
        return try await webView.takeSnapshot(configuration: configuration)
    }

    /// Fallback path: keep the visible viewport size, scroll through the page,
    /// capture viewport-sized tiles, and stitch them. This is more compatible with
    /// large pages, but can duplicate fixed/sticky elements and can trigger lazy-load.
    private func tiledScrollSnapshot(_ webView: WKWebView, pageSize: PageSize, options: Options) async throws -> NSImage {
        let viewportSize = webView.bounds.size
        guard viewportSize.width > 0, viewportSize.height > 0 else { throw CaptureError.invalidPageSize }

        let scale = webView.window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
        let pixelWidth = Int(ceil(pageSize.width * scale))
        let pixelHeight = Int(ceil(pageSize.height * scale))

        guard let context = CGContext(
            data: nil,
            width: pixelWidth,
            height: pixelHeight,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw CaptureError.cgImageUnavailable
        }

        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: 0, y: pageSize.height)
        context.scaleBy(x: 1, y: -1)

        let originalScrollValue = try await webView.evaluateJavaScript("({ x: window.scrollX || 0, y: window.scrollY || 0 })")
        let originalScroll = (originalScrollValue as? [String: Any]) ?? [:]
        let originalX = CGFloat(truncating: (originalScroll["x"] as? NSNumber) ?? 0)
        let originalY = CGFloat(truncating: (originalScroll["y"] as? NSNumber) ?? 0)
        defer {
            Task { @MainActor in
                _ = try? await webView.evaluateJavaScript("window.scrollTo(\(originalX), \(originalY))")
            }
        }

        var y: CGFloat = 0
        while y < pageSize.height {
            let remaining = pageSize.height - y
            let tileHeight = min(viewportSize.height, options.maxTileHeight, remaining)
            _ = try await webView.evaluateJavaScript("window.scrollTo(0, \(y))")
            try await Task.sleep(nanoseconds: options.delayAfterScrollNanoseconds)

            let actualScrollValue = try await webView.evaluateJavaScript("window.scrollY || 0")
            let actualY = CGFloat(truncating: (actualScrollValue as? NSNumber) ?? NSNumber(value: Double(y)))

            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: viewportSize.width, height: tileHeight)
            let tile = try await webView.takeSnapshot(configuration: configuration)
            guard let cgTile = tile.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
                throw CaptureError.cgImageUnavailable
            }

            let drawRect = CGRect(x: 0, y: actualY, width: viewportSize.width, height: tileHeight)
            context.draw(cgTile, in: drawRect)
            y += tileHeight
        }

        guard let combined = context.makeImage() else { throw CaptureError.cgImageUnavailable }
        return NSImage(cgImage: combined, size: CGSize(width: pageSize.width, height: pageSize.height))
    }

    private func pngData(from image: NSImage) throws -> Data {
        guard let tiff = image.tiffRepresentation,
              let bitmap = NSBitmapImageRep(data: tiff),
              let png = bitmap.representation(using: .png, properties: [:]) else {
            throw CaptureError.imageEncodingFailed
        }
        return png
    }
}
