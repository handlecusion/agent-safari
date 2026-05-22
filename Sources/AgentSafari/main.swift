import AgentSafariCore
import AppKit
import Darwin
import Foundation
import WebKit

struct RPCRequest: Codable {
    let id: String?
    let method: String
    let params: [String: String]?
}

struct RPCResponse: Encodable {
    let id: String?
    let ok: Bool
    let result: [String: String]?
    let error: RPCErrorPayload?
}

struct RPCErrorPayload: Encodable {
    let code: String
    let message: String
}

struct ElementHitTarget {
    let viewportCenter: CGPoint
    let viewportBounds: CGRect
    let description: String
}

func stringifyJavaScriptValue(_ value: Any) -> String {
    if let optional = Mirror(reflecting: value).children.first?.value {
        return stringifyJavaScriptValue(optional)
    }
    if value is NSNull {
        return ""
    }
    return String(describing: value)
}

func javaScriptStringLiteral(_ value: String) throws -> String {
    let data = try JSONEncoder().encode(value)
    guard let literal = String(data: data, encoding: .utf8) else {
        throw AgentSafariError.javascriptEncodingFailed
    }
    return literal
}

enum BrowserUserAgentSettings {
    // Always present as Safari. Some WKWebView builds expose a minimal
    // app WebKit user agent without Version/Safari tokens, and Google can serve
    // an unsupported-browser banner or fallback login UI in that case.
    static let safariUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/26.2 Safari/605.1.15"
}

@MainActor
final class BrowserController: NSObject, WKNavigationDelegate {
    private let window: NSWindow
    private let webView: WKWebView
    private var navigationContinuation: CheckedContinuation<Void, Error>?
    private var networkUserScriptInstalled = false
    private var networkCaptureActive = false

    init(focusWindow: Bool = false) {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        self.webView = WKWebView(frame: NSRect(x: 0, y: 0, width: 1280, height: 720), configuration: configuration)
        self.webView.customUserAgent = BrowserUserAgentSettings.safariUserAgent
        self.window = NSWindow(
            contentRect: NSRect(x: 100, y: 100, width: 1280, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        super.init()
        webView.navigationDelegate = self
        window.contentView = webView
        window.title = "Agent Safari"
        if focusWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            window.orderFrontRegardless()
        }
    }

    func navigate(_ urlString: String) async throws -> [String: String] {
        guard let url = URL(string: urlString) else {
            throw AgentSafariError.invalidURL(urlString)
        }
        try await withCheckedThrowingContinuation { continuation in
            navigationContinuation = continuation
            webView.load(URLRequest(url: url))
        }
        return ["url": webView.url?.absoluteString ?? "", "title": webView.title ?? ""]
    }

    func evaluate(_ script: String) async throws -> [String: String] {
        let value = try await webView.evaluateJavaScript(script)
        return ["value": stringifyJavaScriptValue(value as Any)]
    }

    func text() async throws -> [String: String] {
        let value = try await webView.evaluateJavaScript("document.body ? document.body.innerText : ''")
        return ["text": stringifyJavaScriptValue(value as Any)]
    }

    func html() async throws -> [String: String] {
        let value = try await webView.evaluateJavaScript("document.documentElement ? document.documentElement.outerHTML : ''")
        return ["html": stringifyJavaScriptValue(value as Any)]
    }

    func snapshot() async throws -> [String: String] {
        let script = """
        (() => {
          if (!window.__agentSafariSnapshotRefs) {
            window.__agentSafariSnapshotRefs = new WeakMap();
            window.__agentSafariSnapshotNextRef = 1;
          }

          const refFor = (element) => {
            let ref = window.__agentSafariSnapshotRefs.get(element);
            if (!ref) {
              ref = `@e${window.__agentSafariSnapshotNextRef++}`;
              window.__agentSafariSnapshotRefs.set(element, ref);
            }
            return ref;
          };

          const cssEscape = (value) => {
            if (window.CSS && typeof window.CSS.escape === 'function') return window.CSS.escape(value);
            return String(value).replace(/[^a-zA-Z0-9_-]/g, '\\$&');
          };

          const selectorFor = (element) => {
            const tag = (element.tagName || '').toLowerCase();
            if (!tag) return '';
            if (element.id) return `${tag}#${cssEscape(element.id)}`;
            const name = element.getAttribute('name');
            if (name) return `${tag}[name="${String(name).replace(/"/g, '\\"')}"]`;
            const aria = element.getAttribute('aria-label');
            if (aria) return `${tag}[aria-label="${String(aria).replace(/"/g, '\\"')}"]`;
            const role = element.getAttribute('role');
            if (role) return `${tag}[role="${String(role).replace(/"/g, '\\"')}"]`;
            const classes = Array.from(element.classList || []).slice(0, 3).map(cssEscape);
            return classes.length ? `${tag}.${classes.join('.')}` : tag;
          };

          const textFor = (element) => {
            const tag = (element.tagName || '').toLowerCase();
            if (tag === 'input' || tag === 'textarea') {
              return (element.getAttribute('aria-label') || element.getAttribute('placeholder') || element.value || '').trim();
            }
            return (element.innerText || element.textContent || element.getAttribute('aria-label') || element.getAttribute('title') || '').replace(new RegExp('\\\\s+', 'g'), ' ').trim();
          };

          const isCandidate = (element) => {
            const tag = (element.tagName || '').toLowerCase();
            if (['a', 'button', 'input', 'select', 'textarea', 'summary', 'label'].includes(tag)) return true;
            if (element.hasAttribute('role') || element.hasAttribute('onclick') || element.hasAttribute('contenteditable')) return true;
            const tabIndex = element.getAttribute('tabindex');
            return tabIndex !== null && Number(tabIndex) >= 0;
          };

          const isVisible = (element, rect) => {
            const style = window.getComputedStyle(element);
            return style.display !== 'none' && style.visibility !== 'hidden' && Number(style.opacity || '1') > 0 && rect.width > 0 && rect.height > 0;
          };

          const elements = Array.from(document.querySelectorAll('a,button,input,select,textarea,summary,label,[role],[onclick],[tabindex],[contenteditable]'));
          const snapshot = [];
          for (const element of elements) {
            if (!isCandidate(element)) continue;
            const rect = element.getBoundingClientRect();
            if (!isVisible(element, rect)) continue;
            snapshot.push({
              ref: refFor(element),
              tag: (element.tagName || '').toLowerCase(),
              text: textFor(element).slice(0, 200),
              selector: selectorFor(element),
              role: element.getAttribute('role') || '',
              type: element.getAttribute('type') || '',
              name: element.getAttribute('name') || '',
              bounds: {
                x: Math.round(rect.x),
                y: Math.round(rect.y),
                width: Math.round(rect.width),
                height: Math.round(rect.height)
              }
            });
          }
          return JSON.stringify(snapshot);
        })()
        """
        let value = try await webView.evaluateJavaScript(script)
        return ["snapshot": stringifyJavaScriptValue(value as Any)]
    }

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

    private func elementHitTarget(selector: String) async throws -> ElementHitTarget {
        let selectorLiteral = try javaScriptStringLiteral(selector)
        let script = """
        (() => {
          const target = \(selectorLiteral);
          const resolveElement = (target) => {
            if (target.startsWith('@e')) {
              const refs = window.__agentSafariSnapshotRefs;
              if (!refs || typeof refs.get !== 'function') {
                throw new Error(`Snapshot refs are not available for ${target}; run snapshot first.`);
              }

              const candidates = [
                ...document.querySelectorAll('a,button,input,select,textarea,summary,label,[role],[onclick],[tabindex],[contenteditable]'),
                ...document.querySelectorAll('*')
              ];
              const seen = new Set();
              for (const element of candidates) {
                if (seen.has(element)) continue;
                seen.add(element);
                if (refs.get(element) === target) return element;
              }
              throw new Error(`No element found for snapshot ref: ${target}. Run snapshot first or refresh it with snapshot.`);
            }

            const element = document.querySelector(target);
            if (!element) {
              throw new Error(`No element found for selector: ${target}`);
            }
            return element;
          };

          const element = resolveElement(target);
          element.scrollIntoView({ block: 'center', inline: 'center' });
          const rect = element.getBoundingClientRect();
          if (!rect || rect.width <= 0 || rect.height <= 0) {
            throw new Error(`Element has no clickable bounds: ${target}`);
          }
          return {
            x: rect.left,
            y: rect.top,
            width: rect.width,
            height: rect.height,
            centerX: rect.left + rect.width / 2,
            centerY: rect.top + rect.height / 2,
            description: `clicked ${element.tagName || ''}${element.id ? '#' + element.id : ''}`
          };
        })()
        """
        guard let result = try await webView.evaluateJavaScript(script) as? [String: Any] else {
            throw AgentSafariError.elementResolutionFailed(selector)
        }
        let x = CGFloat((result["x"] as? NSNumber)?.doubleValue ?? 0)
        let y = CGFloat((result["y"] as? NSNumber)?.doubleValue ?? 0)
        let width = CGFloat((result["width"] as? NSNumber)?.doubleValue ?? 0)
        let height = CGFloat((result["height"] as? NSNumber)?.doubleValue ?? 0)
        let centerX = CGFloat((result["centerX"] as? NSNumber)?.doubleValue ?? 0)
        let centerY = CGFloat((result["centerY"] as? NSNumber)?.doubleValue ?? 0)
        guard width > 0, height > 0 else { throw AgentSafariError.elementResolutionFailed(selector) }
        return ElementHitTarget(
            viewportCenter: CGPoint(x: centerX, y: centerY),
            viewportBounds: CGRect(x: x, y: y, width: width, height: height),
            description: stringifyJavaScriptValue(result["description"] as Any)
        )
    }

    private func dispatchNativeClick(at target: ElementHitTarget) throws -> [String: String] {
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)

        let viewPoint = CGPoint(x: target.viewportCenter.x, y: webView.bounds.height - target.viewportCenter.y)
        let windowPoint = webView.convert(viewPoint, to: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        guard webView.bounds.contains(viewPoint) else {
            throw AgentSafariError.elementResolutionFailed("offscreen center \(target.viewportCenter)")
        }

        let maxScreenY = NSScreen.screens.map { $0.frame.maxY }.max() ?? screenPoint.y
        let quartzPoint = CGPoint(x: screenPoint.x, y: maxScreenY - screenPoint.y)
        guard let eventSource = CGEventSource(stateID: .combinedSessionState),
              let cgMouseDown = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: quartzPoint, mouseButton: .left),
              let cgMouseUp = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: quartzPoint, mouseButton: .left) else {
            throw AgentSafariError.nativeInputFailed("Failed to create Quartz mouse events")
        }

        cgMouseDown.post(tap: .cghidEventTap)
        cgMouseUp.post(tap: .cghidEventTap)
        return [
            "strategy": "native-quartz",
            "viewportX": String(format: "%.1f", target.viewportCenter.x),
            "viewportY": String(format: "%.1f", target.viewportCenter.y),
            "windowX": String(format: "%.1f", windowPoint.x),
            "windowY": String(format: "%.1f", windowPoint.y),
            "screenX": String(format: "%.1f", screenPoint.x),
            "screenY": String(format: "%.1f", screenPoint.y)
        ]
    }

    private func javaScriptClick(selector: String) async throws -> [String: String] {
        let target = try await elementHitTarget(selector: selector)
        let selectorLiteral = try javaScriptStringLiteral(selector)
        let script = """
        (() => {
          const target = \(selectorLiteral);
          const refs = window.__agentSafariSnapshotRefs;
          const resolveElement = (target) => {
            if (target.startsWith('@e')) {
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
          if (typeof element.focus === 'function') element.focus({ preventScroll: true });
          element.click();
          return true;
        })()
        """
        _ = try await webView.evaluateJavaScript(script)
        return ["strategy": "js-click", "result": target.description]
    }

    private func armNativeClickProbe(selector: String, token: String) async throws {
        let selectorLiteral = try javaScriptStringLiteral(selector)
        let tokenLiteral = try javaScriptStringLiteral(token)
        let script = """
        (() => {
          const target = \(selectorLiteral);
          const token = \(tokenLiteral);
          const refs = window.__agentSafariSnapshotRefs;
          const resolveElement = (target) => {
            if (target.startsWith('@e')) {
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
          window.__agentSafariNativeClickToken = null;
          element.addEventListener('click', () => { window.__agentSafariNativeClickToken = token; }, { capture: true, once: true });
          return true;
        })()
        """
        _ = try await webView.evaluateJavaScript(script)
    }

    private func nativeClickProbeObserved(token: String) async throws -> Bool {
        try await Task.sleep(nanoseconds: 200_000_000)
        let tokenLiteral = try javaScriptStringLiteral(token)
        let script = "window.__agentSafariNativeClickToken === \(tokenLiteral)"
        return (try await webView.evaluateJavaScript(script) as? Bool) ?? false
    }

    func click(selector: String, native: Bool = false) async throws -> [String: String] {
        if native {
            do {
                let target = try await elementHitTarget(selector: selector)
                let token = UUID().uuidString
                try await armNativeClickProbe(selector: selector, token: token)
                let beforeURL = webView.url?.absoluteString ?? ""
                var result = try dispatchNativeClick(at: target)
                let observed: Bool
                do {
                    observed = try await nativeClickProbeObserved(token: token)
                } catch {
                    let afterURL = webView.url?.absoluteString ?? ""
                    if webView.isLoading || afterURL != beforeURL {
                        result["selector"] = selector
                        result["result"] = target.description
                        result["strategy"] = "native-quartz-navigation-assumed"
                        result["beforeURL"] = beforeURL
                        result["afterURL"] = afterURL
                        result["nativeError"] = "Probe failed during navigation: \(describeError(error))"
                        return result
                    }
                    throw error
                }
                if observed {
                    result["selector"] = selector
                    result["result"] = target.description
                    return result
                }
                let afterURL = webView.url?.absoluteString ?? ""
                if webView.isLoading || afterURL != beforeURL {
                    result["selector"] = selector
                    result["result"] = target.description
                    result["strategy"] = "native-quartz-navigation-assumed"
                    result["beforeURL"] = beforeURL
                    result["afterURL"] = afterURL
                    return result
                }
                var fallback = try await javaScriptClick(selector: selector)
                fallback["selector"] = selector
                fallback["strategy"] = "native-unobserved-js-click"
                fallback["nativeError"] = "Native Quartz click posted but no DOM click event was observed"
                return fallback
            } catch {
                var fallback = try await javaScriptClick(selector: selector)
                fallback["selector"] = selector
                fallback["strategy"] = "native-failed-js-click"
                fallback["nativeError"] = describeError(error)
                return fallback
            }
        }

        var result = try await javaScriptClick(selector: selector)
        result["selector"] = selector
        return result
    }

    func fill(selector: String, value: String) async throws -> [String: String] {
        let selectorLiteral = try javaScriptStringLiteral(selector)
        let valueLiteral = try javaScriptStringLiteral(value)
        let script = """
        (() => {
          const target = \(selectorLiteral);
          const value = \(valueLiteral);
          const resolveElement = (target) => {
            if (target.startsWith('@e')) {
              const refs = window.__agentSafariSnapshotRefs;
              if (!refs || typeof refs.get !== 'function') {
                throw new Error(`Snapshot refs are not available for ${target}; run snapshot first.`);
              }

              const candidates = [
                ...document.querySelectorAll('a,button,input,select,textarea,summary,label,[role],[onclick],[tabindex],[contenteditable]'),
                ...document.querySelectorAll('*')
              ];
              const seen = new Set();
              for (const element of candidates) {
                if (seen.has(element)) continue;
                seen.add(element);
                if (refs.get(element) === target) return element;
              }
              throw new Error(`No element found for snapshot ref: ${target}. Run snapshot first or refresh it with snapshot.`);
            }

            const element = document.querySelector(target);
            if (!element) {
              throw new Error(`No element found for selector: ${target}`);
            }
            return element;
          };

          const element = resolveElement(target);
          element.scrollIntoView({ block: 'center', inline: 'center' });
          if (typeof element.focus === 'function') element.focus({ preventScroll: true });
          element.value = value;
          element.dispatchEvent(new Event('input', { bubbles: true }));
          element.dispatchEvent(new Event('change', { bubbles: true }));
          return element.value || '';
        })()
        """
        let jsResult = try await webView.evaluateJavaScript(script)
        return ["selector": selector, "value": stringifyJavaScriptValue(jsResult as Any)]
    }

    func key(_ key: String) async throws -> [String: String] {
        let keyLiteral = try javaScriptStringLiteral(key)
        let script = """
        (() => {
          const key = \(keyLiteral);
          const target = document.activeElement || document.body;
          let defaultPrevented = false;
          for (const type of ['keydown', 'keypress', 'keyup']) {
            const event = new KeyboardEvent(type, { key, bubbles: true, cancelable: true });
            target.dispatchEvent(event);
            defaultPrevented = defaultPrevented || event.defaultPrevented;
          }
          return { key, target: (target && target.tagName) || '', defaultPrevented };
        })()
        """
        guard let result = try await webView.evaluateJavaScript(script) as? [String: Any] else {
            return ["key": key, "strategy": "synthetic-key"]
        }
        return [
            "key": stringifyJavaScriptValue(result["key"] as Any),
            "target": stringifyJavaScriptValue(result["target"] as Any),
            "defaultPrevented": stringifyJavaScriptValue(result["defaultPrevented"] as Any),
            "strategy": "synthetic-key"
        ]
    }

    func typeText(_ text: String) async throws -> [String: String] {
        let textLiteral = try javaScriptStringLiteral(text)
        let script = """
        (() => {
          const text = \(textLiteral);
          const target = document.activeElement || document.body;
          if (!target) throw new Error('No active element to type into');
          if (target.isContentEditable) {
            document.execCommand('insertText', false, text);
            return { value: target.textContent || '', target: target.tagName || '', mode: 'contenteditable' };
          }
          const tag = (target.tagName || '').toLowerCase();
          if (tag === 'input' || tag === 'textarea') {
            const start = Number.isFinite(target.selectionStart) ? target.selectionStart : String(target.value || '').length;
            const end = Number.isFinite(target.selectionEnd) ? target.selectionEnd : start;
            const current = String(target.value || '');
            target.value = current.slice(0, start) + text + current.slice(end);
            const cursor = start + text.length;
            if (typeof target.setSelectionRange === 'function') target.setSelectionRange(cursor, cursor);
            target.dispatchEvent(new InputEvent('input', { bubbles: true, cancelable: true, data: text, inputType: 'insertText' }));
            target.dispatchEvent(new Event('change', { bubbles: true }));
            return { value: target.value || '', target: target.tagName || '', mode: 'value' };
          }
          for (const ch of Array.from(text)) {
            for (const type of ['keydown', 'keypress', 'keyup']) {
              target.dispatchEvent(new KeyboardEvent(type, { key: ch, bubbles: true, cancelable: true }));
            }
          }
          return { value: '', target: target.tagName || '', mode: 'synthetic-key-events' };
        })()
        """
        guard let result = try await webView.evaluateJavaScript(script) as? [String: Any] else {
            return ["text": text, "strategy": "synthetic-type"]
        }
        return [
            "text": text,
            "value": stringifyJavaScriptValue(result["value"] as Any),
            "target": stringifyJavaScriptValue(result["target"] as Any),
            "mode": stringifyJavaScriptValue(result["mode"] as Any),
            "strategy": "synthetic-type"
        ]
    }

    func wait(ms: Int) async throws -> [String: String] {
        let clampedMs = min(max(0, ms), 86_400_000)
        try await Task.sleep(nanoseconds: UInt64(clampedMs) * 1_000_000)
        return ["waitedMs": String(clampedMs)]
    }

    func waitForSelector(_ selector: String, timeoutMs: Int) async throws -> [String: String] {
        let selectorLiteral = try javaScriptStringLiteral(selector)
        let script = "document.querySelector(\(selectorLiteral)) !== null"
        try await waitUntil(timeoutMs: timeoutMs) {
            let value = try await self.webView.evaluateJavaScript(script)
            return (value as? Bool) == true
        }
        return ["selector": selector, "found": "true", "timeoutMs": String(max(0, timeoutMs))]
    }

    func waitForText(_ text: String, timeoutMs: Int) async throws -> [String: String] {
        let textLiteral = try javaScriptStringLiteral(text)
        let script = "(document.body ? document.body.innerText : '').includes(\(textLiteral))"
        try await waitUntil(timeoutMs: timeoutMs) {
            let value = try await self.webView.evaluateJavaScript(script)
            return (value as? Bool) == true
        }
        return ["text": text, "found": "true", "timeoutMs": String(max(0, timeoutMs))]
    }

    func waitForIdle(timeoutMs: Int) async throws -> [String: String] {
        let quietWindowMs = 500
        var idleSince: Date?
        try await waitUntil(timeoutMs: timeoutMs) {
            let readyStateValue = try await self.webView.evaluateJavaScript("document.readyState")
            let pendingValue = try await self.webView.evaluateJavaScript("window.__agentSafariNetworkPending || 0")
            let readyState = stringifyJavaScriptValue(readyStateValue as Any)
            let pending = (pendingValue as? NSNumber)?.intValue ?? 0
            let currentlyIdle = !self.webView.isLoading && readyState == "complete" && pending == 0

            if currentlyIdle {
                let now = Date()
                if let since = idleSince, now.timeIntervalSince(since) * 1000 >= Double(quietWindowMs) {
                    return true
                }
                if idleSince == nil {
                    idleSince = now
                }
            } else {
                idleSince = nil
            }
            return false
        }
        return ["idle": "true", "timeoutMs": String(max(0, timeoutMs)), "quietWindowMs": String(quietWindowMs)]
    }

    private func waitUntil(timeoutMs: Int, condition: () async throws -> Bool) async throws {
        let clampedTimeoutMs = max(0, timeoutMs)
        let deadline = Date().addingTimeInterval(Double(clampedTimeoutMs) / 1000.0)
        repeat {
            if try await condition() {
                return
            }
            if Date() >= deadline {
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while true
        throw AgentSafariError.waitTimedOut(clampedTimeoutMs)
    }

    func status() async throws -> [String: String] {
        return [
            "url": webView.url?.absoluteString ?? "",
            "title": webView.title ?? "",
            "loading": webView.isLoading ? "true" : "false"
        ]
    }

    func observe() async throws -> [String: String] {
        let script = """
        (() => {
          const active = document.activeElement;
          return {
            readyState: document.readyState || '',
            activeElementTag: active && active.tagName ? active.tagName.toLowerCase() : '',
            activeElementType: active && active.getAttribute ? (active.getAttribute('type') || '') : '',
            activeElementName: active && active.getAttribute ? (active.getAttribute('name') || '') : '',
            activeElementId: active && active.id ? active.id : ''
          };
        })()
        """
        let pageState = try await webView.evaluateJavaScript(script) as? [String: Any]
        let networkCapturing = try await networkCapturingString()
        return [
            "url": webView.url?.absoluteString ?? "",
            "title": webView.title ?? "",
            "readyState": stringifyJavaScriptValue((pageState?["readyState"] ?? "") as Any),
            "isLoading": webView.isLoading ? "true" : "false",
            "networkCapturing": networkCapturing,
            "activeElementTag": stringifyJavaScriptValue((pageState?["activeElementTag"] ?? "") as Any),
            "activeElementType": stringifyJavaScriptValue((pageState?["activeElementType"] ?? "") as Any),
            "activeElementName": stringifyJavaScriptValue((pageState?["activeElementName"] ?? "") as Any),
            "activeElementId": stringifyJavaScriptValue((pageState?["activeElementId"] ?? "") as Any)
        ]
    }

    func networkStart() async throws -> [String: String] {
        let script = BrowserController.networkInstrumentationScript
        if !networkUserScriptInstalled {
            let userScript = WKUserScript(source: script + "\nwindow.__agentSafariNetworkCaptureEnabled = true;", injectionTime: .atDocumentStart, forMainFrameOnly: true)
            webView.configuration.userContentController.addUserScript(userScript)
            networkUserScriptInstalled = true
        }
        networkCaptureActive = true
        _ = try await webView.evaluateJavaScript(script)
        _ = try await webView.evaluateJavaScript("window.__agentSafariNetworkCaptureEnabled = true; if (window.__agentSafariNetworkEvents) window.__agentSafariNetworkEvents.length = 0; true")
        return ["capturing": "true", "events": "[]", "count": "0"]
    }

    func networkList() async throws -> [String: String] {
        let value = try await webView.evaluateJavaScript("JSON.stringify(window.__agentSafariNetworkEvents || [])")
        let events = stringifyJavaScriptValue(value as Any)
        let countValue = try await webView.evaluateJavaScript("(window.__agentSafariNetworkEvents || []).length")
        return ["capturing": try await networkCapturingString(), "events": events, "count": stringifyJavaScriptValue(countValue as Any)]
    }

    func networkStop() async throws -> [String: String] {
        let list = try await networkList()
        networkCaptureActive = false
        webView.configuration.userContentController.removeAllUserScripts()
        networkUserScriptInstalled = false
        _ = try await webView.evaluateJavaScript("window.__agentSafariNetworkCaptureEnabled = false; true")
        return ["capturing": "false", "events": list["events"] ?? "[]", "count": list["count"] ?? "0"]
    }

    private func networkCapturingString() async throws -> String {
        let value = try await webView.evaluateJavaScript("window.__agentSafariNetworkCaptureEnabled === true")
        if let boolValue = value as? Bool {
            return boolValue ? "true" : "false"
        }
        if let numberValue = value as? NSNumber {
            return numberValue.boolValue ? "true" : "false"
        }
        return "false"
    }

    private static let networkInstrumentationScript = """
    (function installAgentSafariNetworkCapture(global) {
      'use strict';
      if (!global) return;
      global.__agentSafariNetworkEvents = global.__agentSafariNetworkEvents || [];
      global.__agentSafariNetworkNextId = global.__agentSafariNetworkNextId || 1;
      global.__agentSafariNetworkPending = global.__agentSafariNetworkPending || 0;
      global.__agentSafariNetworkCaptureEnabled = global.__agentSafariNetworkCaptureEnabled === true;
      if (global.__agentSafariNetworkCaptureInstalled) return;
      var MAX_ENTRIES = 1000;
      var MAX_BODY_PREVIEW = 4096;
      var originalFetch = global.fetch;
      var OriginalXMLHttpRequest = global.XMLHttpRequest;
      function now() { return global.performance && typeof global.performance.now === 'function' ? global.performance.now() : Date.now(); }
      function headersToObject(headers) {
        var out = {};
        if (!headers) return out;
        try {
          if (typeof headers.forEach === 'function') { headers.forEach(function(v, k) { out[String(k).toLowerCase()] = String(v); }); return out; }
          if (Array.isArray(headers)) { headers.forEach(function(pair) { if (pair && pair.length >= 2) out[String(pair[0]).toLowerCase()] = String(pair[1]); }); return out; }
          Object.keys(headers).forEach(function(k) { out[String(k).toLowerCase()] = String(headers[k]); });
        } catch (_) {}
        return out;
      }
      function bodyPreview(value) {
        if (value == null) return undefined;
        try {
          if (typeof value === 'string') return value.slice(0, MAX_BODY_PREVIEW);
          if (value instanceof URLSearchParams) return value.toString().slice(0, MAX_BODY_PREVIEW);
          if (value instanceof FormData) { var fields = []; value.forEach(function(v, k) { fields.push([String(k), v instanceof File ? '[File:' + v.name + ']' : String(v)]); }); return JSON.stringify(fields).slice(0, MAX_BODY_PREVIEW); }
          if (value instanceof Blob) return '[Blob size=' + value.size + ' type=' + value.type + ']';
          if (value instanceof ArrayBuffer) return '[ArrayBuffer byteLength=' + value.byteLength + ']';
        } catch (_) {}
        return Object.prototype.toString.call(value);
      }
      function push(entry) {
        if (!global.__agentSafariNetworkCaptureEnabled) return entry;
        entry.id = global.__agentSafariNetworkNextId++;
        entry.wallTime = new Date().toISOString();
        global.__agentSafariNetworkEvents.push(entry);
        if (global.__agentSafariNetworkEvents.length > MAX_ENTRIES) global.__agentSafariNetworkEvents.splice(0, global.__agentSafariNetworkEvents.length - MAX_ENTRIES);
        return entry;
      }
      function incrementPending() { global.__agentSafariNetworkPending = Math.max(0, (global.__agentSafariNetworkPending || 0) + 1); }
      function decrementPending() { global.__agentSafariNetworkPending = Math.max(0, (global.__agentSafariNetworkPending || 0) - 1); }
      global.__agentSafariNetworkCaptureInstalled = true;
      global.__agentSafariNetwork = { list: function() { return global.__agentSafariNetworkEvents.slice(); }, clear: function() { global.__agentSafariNetworkEvents.length = 0; return true; }, export: function() { return JSON.stringify(global.__agentSafariNetworkEvents, null, 2); } };
      try { if (typeof originalFetch === 'function') {
        global.fetch = function agentSafariFetch(input, init) {
          var request, url = '', method = 'GET', requestHeaders = {}, requestBodyPreview, startedAt = now();
          try { request = input instanceof Request ? input : null; url = request ? request.url : String(input); method = (init && init.method) || (request && request.method) || method; requestHeaders = Object.assign({}, headersToObject(request && request.headers), headersToObject(init && init.headers)); requestBodyPreview = bodyPreview(init && Object.prototype.hasOwnProperty.call(init, 'body') ? init.body : request && request.body); } catch (_) { url = String(input); }
          var entry = push({ type: 'fetch', phase: 'request', method: String(method || 'GET').toUpperCase(), url: url, requestHeaders: requestHeaders, requestBodyPreview: requestBodyPreview, startedAt: startedAt });
          incrementPending();
          return originalFetch.apply(this, arguments).then(function(response) { decrementPending(); entry.phase = 'response'; entry.status = response.status; entry.statusText = response.statusText; entry.ok = response.ok; entry.responseURL = response.url; entry.responseHeaders = headersToObject(response.headers); entry.endedAt = now(); entry.durationMs = Math.round((entry.endedAt - startedAt) * 1000) / 1000; return response; }, function(error) { decrementPending(); entry.phase = 'error'; entry.error = error && (error.stack || error.message || String(error)); entry.endedAt = now(); entry.durationMs = Math.round((entry.endedAt - startedAt) * 1000) / 1000; throw error; });
        };
      } } catch (_) {}
      try { if (typeof OriginalXMLHttpRequest === 'function') {
        global.XMLHttpRequest = function AgentSafariXMLHttpRequest() {
          var xhr = new OriginalXMLHttpRequest();
          var entry = null, requestHeaders = {}, startedAt = 0;
          var originalOpen = xhr.open, originalSend = xhr.send, originalSetRequestHeader = xhr.setRequestHeader;
          xhr.open = function(method, url) { entry = { type: 'xhr', phase: 'opened', method: String(method || 'GET').toUpperCase(), url: String(url || ''), requestHeaders: requestHeaders }; return originalOpen.apply(xhr, arguments); };
          xhr.setRequestHeader = function(name, value) { requestHeaders[String(name).toLowerCase()] = String(value); return originalSetRequestHeader.apply(xhr, arguments); };
          xhr.send = function(body) { startedAt = now(); if (!entry) entry = { type: 'xhr', method: 'GET', url: '', requestHeaders: requestHeaders }; entry.phase = 'request'; entry.requestBodyPreview = bodyPreview(body); entry.startedAt = startedAt; push(entry); incrementPending(); return originalSend.apply(xhr, arguments); };
          xhr.addEventListener('loadend', function() { decrementPending(); if (!entry) return; entry.phase = xhr.status === 0 ? 'error-or-cancel' : 'response'; entry.status = xhr.status; entry.statusText = xhr.statusText; entry.responseURL = xhr.responseURL; entry.endedAt = now(); entry.durationMs = Math.round((entry.endedAt - startedAt) * 1000) / 1000; try { var headers = {}; xhr.getAllResponseHeaders().trim().split(String.fromCharCode(10)).forEach(function(line) { line = line.replace(String.fromCharCode(13), ''); var idx = line.indexOf(':'); if (idx > 0) headers[line.slice(0, idx).trim().toLowerCase()] = line.slice(idx + 1).trim(); }); entry.responseHeaders = headers; } catch (_) {} });
          return xhr;
        };
        try { global.XMLHttpRequest.prototype = OriginalXMLHttpRequest.prototype; } catch (_) {}
      } } catch (_) {}
    })(typeof window !== 'undefined' ? window : this);
    """

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        navigationContinuation?.resume()
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        navigationContinuation?.resume(throwing: error)
        navigationContinuation = nil
    }
}

enum AgentSafariError: Error, LocalizedError {
    case invalidURL(String)
    case missingParam(String)
    case screenshotFailed
    case pageMeasurementFailed
    case javascriptEncodingFailed
    case invalidIntegerParam(String, String)
    case waitTimedOut(Int)
    case elementResolutionFailed(String)
    case nativeInputFailed(String)
    case unknownMethod(String)
    case socketPathTooLong(String)
    case socketOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .invalidURL(let value): return "Invalid URL: \(value)"
        case .missingParam(let name): return "Missing param: \(name)"
        case .screenshotFailed: return "Failed to encode screenshot as PNG"
        case .pageMeasurementFailed: return "Failed to measure page dimensions"
        case .javascriptEncodingFailed: return "Failed to encode JavaScript string literal"
        case .invalidIntegerParam(let name, let value): return "Invalid integer for \(name): \(value)"
        case .waitTimedOut(let timeoutMs): return "Timed out after \(timeoutMs) ms"
        case .elementResolutionFailed(let target): return "Failed to resolve clickable element: \(target)"
        case .nativeInputFailed(let message): return "Native input failed: \(message)"
        case .unknownMethod(let method): return "Unknown method: \(method)"
        case .socketPathTooLong(let path): return "Unix socket path is too long: \(path)"
        case .socketOperationFailed(let message): return message
        }
    }
}

func describeError(_ error: Error) -> String {
    let nsError = error as NSError
    if let message = nsError.userInfo["WKJavaScriptExceptionMessage"] as? String {
        let line = nsError.userInfo["WKJavaScriptExceptionLineNumber"].map { String(describing: $0) } ?? "?"
        return "JavaScript exception at line \(line): \(message)"
    }
    return error.localizedDescription
}

func parseNonNegativeIntParam(_ params: [String: String], name: String, defaultValue: Int? = nil) throws -> Int {
    guard let value = params[name] else {
        if let defaultValue { return defaultValue }
        throw AgentSafariError.missingParam(name)
    }
    guard let intValue = Int(value), intValue >= 0 else {
        throw AgentSafariError.invalidIntegerParam(name, value)
    }
    return intValue
}

@MainActor
func handle(_ request: RPCRequest, browser: BrowserController) async -> RPCResponse {
    do {
        let params = request.params ?? [:]
        let result: [String: String]
        switch request.method {
        case "navigate":
            guard let url = params["url"] else { throw AgentSafariError.missingParam("url") }
            result = try await browser.navigate(url)
        case "evaluate":
            guard let script = params["script"] else { throw AgentSafariError.missingParam("script") }
            result = try await browser.evaluate(script)
        case "text":
            result = try await browser.text()
        case "html":
            result = try await browser.html()
        case "snapshot":
            result = try await browser.snapshot()
        case "screenshot":
            let path = params["path"] ?? "\(NSHomeDirectory())/.agent-safari/artifacts/screenshot.png"
            result = try await browser.screenshot(path: path)
        case "screenshotFull":
            let path = params["path"] ?? "\(NSHomeDirectory())/.agent-safari/artifacts/screenshot-full.png"
            result = try await browser.screenshotFull(path: path)
        case "click":
            guard let selector = params["selector"] else { throw AgentSafariError.missingParam("selector") }
            result = try await browser.click(selector: selector, native: params["native"] == "true")
        case "fill":
            guard let selector = params["selector"] else { throw AgentSafariError.missingParam("selector") }
            guard let value = params["value"] else { throw AgentSafariError.missingParam("value") }
            result = try await browser.fill(selector: selector, value: value)
        case "key":
            guard let key = params["key"] else { throw AgentSafariError.missingParam("key") }
            result = try await browser.key(key)
        case "type":
            guard let text = params["text"] else { throw AgentSafariError.missingParam("text") }
            result = try await browser.typeText(text)
        case "wait":
            let ms = try parseNonNegativeIntParam(params, name: "ms")
            result = try await browser.wait(ms: ms)
        case "waitForSelector":
            guard let selector = params["selector"] else { throw AgentSafariError.missingParam("selector") }
            let timeoutMs = try parseNonNegativeIntParam(params, name: "timeoutMs", defaultValue: 10_000)
            result = try await browser.waitForSelector(selector, timeoutMs: timeoutMs)
        case "waitForText":
            guard let text = params["text"] else { throw AgentSafariError.missingParam("text") }
            let timeoutMs = try parseNonNegativeIntParam(params, name: "timeoutMs", defaultValue: 10_000)
            result = try await browser.waitForText(text, timeoutMs: timeoutMs)
        case "waitForIdle":
            let timeoutMs = try parseNonNegativeIntParam(params, name: "timeoutMs", defaultValue: 10_000)
            result = try await browser.waitForIdle(timeoutMs: timeoutMs)
        case "networkStart":
            result = try await browser.networkStart()
        case "networkStop":
            result = try await browser.networkStop()
        case "networkList":
            result = try await browser.networkList()
        case "status":
            result = try await browser.status()
        case "observe":
            result = try await browser.observe()
        default:
            throw AgentSafariError.unknownMethod(request.method)
        }
        return RPCResponse(id: request.id, ok: true, result: result, error: nil)
    } catch {
        return RPCResponse(
            id: request.id,
            ok: false,
            result: nil,
            error: RPCErrorPayload(code: "error", message: describeError(error))
        )
    }
}

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

func sendClient(method: String, params: [String: String], socketPath: String) throws {
    let fd = socket(AF_UNIX, SOCK_STREAM, 0)
    guard fd >= 0 else { throw AgentSafariError.socketOperationFailed(lastErrnoMessage("socket")) }
    defer { close(fd) }

    var address = try makeUnixAddress(path: socketPath)
    let connectResult = withSockaddr(&address) { sockaddrPointer, length in
        Darwin.connect(fd, sockaddrPointer, length)
    }
    guard connectResult == 0 else {
        throw AgentSafariError.socketOperationFailed(lastErrnoMessage("connect"))
    }

    let request = RPCRequest(id: UUID().uuidString, method: method, params: params)
    var payload = try JSONEncoder().encode(request)
    payload.append(10)
    writeAll(fd: fd, data: payload)

    if let response = readLineFromFD(fd), let text = String(data: response, encoding: .utf8) {
        print(text.trimmingCharacters(in: .whitespacesAndNewlines))
    }
}

func usage() {
    print("""
    agent-safari daemon [--focus-window] [--socket /tmp/agent-safari.sock]
    agent-safari navigate <url> [--socket /tmp/agent-safari.sock]
    agent-safari text [--socket /tmp/agent-safari.sock]
    agent-safari html [--socket /tmp/agent-safari.sock]
    agent-safari snapshot [--socket /tmp/agent-safari.sock]
    agent-safari evaluate <javascript> [--socket /tmp/agent-safari.sock]
    agent-safari screenshot <path> [--socket /tmp/agent-safari.sock]
    agent-safari screenshot-full <path> [--socket /tmp/agent-safari.sock]
    agent-safari click <selector> [--native] [--socket /tmp/agent-safari.sock]
    agent-safari fill <selector> <value> [--socket /tmp/agent-safari.sock]
    agent-safari key <key> [--socket /tmp/agent-safari.sock]
    agent-safari type <text> [--socket /tmp/agent-safari.sock]
    agent-safari wait <ms> [--socket /tmp/agent-safari.sock]
    agent-safari wait-for-selector <selector> [--timeout <ms>] [--socket /tmp/agent-safari.sock]
    agent-safari wait-for-text <text> [--timeout <ms>] [--socket /tmp/agent-safari.sock]
    agent-safari wait-for-idle [--timeout <ms>] [--socket /tmp/agent-safari.sock]
    agent-safari network-start [--socket /tmp/agent-safari.sock]
    agent-safari network-list [--socket /tmp/agent-safari.sock]
    agent-safari network-stop [--socket /tmp/agent-safari.sock]
    agent-safari status [--socket /tmp/agent-safari.sock]
    agent-safari observe [--socket /tmp/agent-safari.sock]
    """)
}

let options = CLIOptions.parse(Array(CommandLine.arguments.dropFirst()))
let args = options.positionalArguments

if args.first == "daemon" {
    let app = NSApplication.shared
    app.setActivationPolicy(.regular)
    let browser = BrowserController(focusWindow: options.focusWindow)
    let server = UnixSocketServer(path: options.socketPath, browser: browser)
    try server.start()
    app.run()
} else if ["navigate", "text", "html", "snapshot", "evaluate", "screenshot", "screenshot-full", "click", "fill", "key", "type", "wait", "wait-for-selector", "wait-for-text", "wait-for-idle", "network-start", "network-list", "network-stop", "status", "observe"].contains(args.first ?? "") {
    do {
        let command = try CommandRequest.parse(args)
        try sendClient(method: command.method, params: command.params, socketPath: options.socketPath)
    } catch {
        fputs("\(error.localizedDescription)\n", stderr)
        usage()
        exit(1)
    }
} else {
    usage()
}
