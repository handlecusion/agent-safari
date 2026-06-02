import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    func screenshot(path: String) async throws -> [String: String] {
        let pageSize = try await measurePageSize()
        let configuration = WKSnapshotConfiguration()
        configuration.rect = webView.bounds
        let image = try await webView.takeSnapshot(configuration: configuration)
        let url = try writePNG(image, path: path)
        return screenshotMetadata(
            url: url,
            fullPage: false,
            captureSize: webView.bounds.size,
            pageSize: pageSize,
            strategy: "viewport",
            tileCount: 1,
            warnings: []
        ).merging([
            "path": url.path,
            "fullPage": "false",
            "width": String(Int(webView.bounds.width.rounded())),
            "height": String(Int(webView.bounds.height.rounded())),
            "strategy": "viewport"
        ]) { _, new in new }
    }

    func screenshotFull(path: String) async throws -> [String: String] {
        let pageSize = try await measurePageSize()
        let preflightScrollCount = try await preflightFullPageCapture(pageSize: pageSize)
        let maxSingleSnapshotPixels: CGFloat = 16_000_000
        let pixelArea = pageSize.width * pageSize.height

        if pixelArea <= maxSingleSnapshotPixels {
            let configuration = WKSnapshotConfiguration()
            configuration.rect = NSRect(x: 0, y: 0, width: pageSize.width, height: pageSize.height)
            let image = try await webView.takeSnapshot(configuration: configuration)
            let url = try writePNG(image, path: path)
            return screenshotMetadata(
                url: url,
                fullPage: true,
                captureSize: pageSize,
                pageSize: pageSize,
                strategy: "single-rect",
                tileCount: 1,
                warnings: []
            ).merging([
                "path": url.path,
                "fullPage": "true",
                "width": String(Int(pageSize.width.rounded())),
                "height": String(Int(pageSize.height.rounded())),
                "strategy": "single-rect",
                "tiles": "1",
                "tileCount": "1",
                "preflightScrollCount": String(preflightScrollCount)
            ]) { _, new in new }
        }

        let url = try await writeTiledFullPageScreenshot(pageSize: pageSize, path: path)
        let tileCount = max(1, Int(ceil(pageSize.height / max(1, webView.bounds.height))))
        return screenshotMetadata(
            url: url,
            fullPage: true,
            captureSize: pageSize,
            pageSize: pageSize,
            strategy: "tiled-scroll",
            tileCount: tileCount,
            warnings: pageSize.width > webView.bounds.width ? ["page width exceeds viewport; tiled capture clamps to viewport width"] : []
        ).merging([
            "path": url.path,
            "fullPage": "true",
            "width": String(Int(pageSize.width.rounded())),
            "height": String(Int(pageSize.height.rounded())),
            "strategy": "tiled-scroll",
            "tiles": String(tileCount),
            "tileCount": String(tileCount),
            "preflightScrollCount": String(preflightScrollCount)
        ]) { _, new in new }
    }

    func screenshotElement(selector: String, path: String) async throws -> [String: String] {
        let selectorLiteral = try javaScriptStringLiteral(selector)
        let script = """
        (() => {
          const target = \(selectorLiteral);
          const resolveElement = (target) => {
            if (target.startsWith('@e')) {
              const refs = window.__agentSafariSnapshotRefs;
              if (!refs || typeof refs.get !== 'function') throw new Error(`Snapshot refs are not available for ${target}; run snapshot first.`);
              const candidates = [...document.querySelectorAll('a,button,input,select,textarea,summary,label,[role],[onclick],[tabindex],[contenteditable]'), ...document.querySelectorAll('*')];
              const seen = new Set();
              for (const element of candidates) {
                if (seen.has(element)) continue;
                seen.add(element);
                if (refs.get(element) === target) return element;
              }
              throw new Error(`No element found for snapshot ref: ${target}. Run snapshot first or refresh it with snapshot.`);
            }
            const element = document.querySelector(target);
            if (!element) throw new Error(`No element found for selector: ${target}`);
            return element;
          };
          const element = resolveElement(target);
          element.scrollIntoView({ block: 'center', inline: 'center' });
          const rect = element.getBoundingClientRect();
          if (!rect || rect.width <= 0 || rect.height <= 0) throw new Error(`Element has no screenshot bounds: ${target}`);
          return { x: rect.x, y: rect.y, width: rect.width, height: rect.height };
        })()
        """
        guard let result = try await webView.evaluateJavaScript(script) as? [String: Any] else {
            throw AgentSafariError.elementResolutionFailed(selector)
        }
        let rect = NSRect(
            x: CGFloat((result["x"] as? NSNumber)?.doubleValue ?? 0),
            y: CGFloat((result["y"] as? NSNumber)?.doubleValue ?? 0),
            width: CGFloat((result["width"] as? NSNumber)?.doubleValue ?? 0),
            height: CGFloat((result["height"] as? NSNumber)?.doubleValue ?? 0)
        ).intersection(webView.bounds)
        guard rect.width > 0, rect.height > 0 else { throw AgentSafariError.elementResolutionFailed(selector) }
        let pageSize = try await measurePageSize()
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        let image = try await webView.takeSnapshot(configuration: configuration)
        let url = try writePNG(image, path: path)
        return screenshotMetadata(
            url: url,
            fullPage: false,
            captureSize: rect.size,
            pageSize: pageSize,
            strategy: "element-rect",
            tileCount: 1,
            warnings: []
        ).merging([
            "path": url.path,
            "fullPage": "false",
            "element": selector,
            "width": String(Int(rect.width.rounded())),
            "height": String(Int(rect.height.rounded())),
            "x": String(Int(rect.origin.x.rounded())),
            "y": String(Int(rect.origin.y.rounded())),
            "strategy": "element-rect"
        ]) { _, new in new }
    }

    private func screenshotMetadata(url: URL, fullPage: Bool, captureSize: CGSize, pageSize: CGSize, strategy: String, tileCount: Int, warnings: [String]) -> [String: String] {
        let viewport = webView.bounds.size
        let warningsValue: String
        if let data = try? JSONSerialization.data(withJSONObject: warnings),
           let encoded = String(data: data, encoding: .utf8) {
            warningsValue = encoded
        } else {
            warningsValue = "[]"
        }
        return [
            "path": url.path,
            "outputPath": url.path,
            "fullPage": fullPage ? "true" : "false",
            "width": String(Int(captureSize.width.rounded())),
            "height": String(Int(captureSize.height.rounded())),
            "viewportWidth": String(Int(viewport.width.rounded())),
            "viewportHeight": String(Int(viewport.height.rounded())),
            "pageWidth": String(Int(pageSize.width.rounded())),
            "pageHeight": String(Int(pageSize.height.rounded())),
            "scale": String(format: "%.3f", window.backingScaleFactor),
            "tileCount": String(tileCount),
            "warnings": warningsValue,
            "strategy": strategy
        ]
    }

    private func preflightFullPageCapture(pageSize: CGSize) async throws -> Int {
        let viewportHeight = max(1, webView.bounds.height)
        guard pageSize.height > viewportHeight else { return 0 }
        let originalScrollValue = try await webView.evaluateJavaScript("({ x: window.scrollX || 0, y: window.scrollY || 0 })")
        let originalScroll = originalScrollValue as? [String: Any]
        let originalX = Int(CGFloat((originalScroll?["x"] as? NSNumber)?.doubleValue ?? 0).rounded())
        let originalY = Int(CGFloat((originalScroll?["y"] as? NSNumber)?.doubleValue ?? 0).rounded())
        let maxScrollY = max(0, pageSize.height - viewportHeight)
        let step = max(1, viewportHeight * 0.8)
        var positions: [Int] = []
        var y: CGFloat = 0
        while y < maxScrollY {
            positions.append(Int(y.rounded()))
            y += step
        }
        positions.append(Int(maxScrollY.rounded()))
        for position in positions {
            _ = try await webView.evaluateJavaScript("window.scrollTo(\(originalX), \(position)); true")
            try await Task.sleep(nanoseconds: 60_000_000)
        }
        _ = try await webView.evaluateJavaScript("window.scrollTo(\(originalX), \(originalY)); true")
        try await Task.sleep(nanoseconds: 60_000_000)
        return positions.count
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
