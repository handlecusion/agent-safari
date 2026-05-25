import AgentSafariCore
import AppKit
import Foundation
import WebKit
import Darwin

@MainActor
extension BrowserController {
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
        window.makeFirstResponder(webView)
        NSApp.activate(ignoringOtherApps: true)

        let viewPoint = CGPoint(x: target.viewportCenter.x, y: webView.bounds.height - target.viewportCenter.y)
        let windowPoint = webView.convert(viewPoint, to: nil)
        let screenPoint = window.convertPoint(toScreen: windowPoint)
        guard webView.bounds.contains(viewPoint) else {
            throw AgentSafariError.elementResolutionFailed("offscreen center \(target.viewportCenter)")
        }

        let maxScreenY = NSScreen.screens.map { $0.frame.maxY }.max() ?? screenPoint.y
        let quartzPoint = CGPoint(x: screenPoint.x, y: maxScreenY - screenPoint.y)
        if let eventSource = CGEventSource(stateID: .combinedSessionState),
           let cgMouseMove = CGEvent(mouseEventSource: eventSource, mouseType: .mouseMoved, mouseCursorPosition: quartzPoint, mouseButton: .left),
           let cgMouseDown = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseDown, mouseCursorPosition: quartzPoint, mouseButton: .left),
           let cgMouseUp = CGEvent(mouseEventSource: eventSource, mouseType: .leftMouseUp, mouseCursorPosition: quartzPoint, mouseButton: .left) {
            cgMouseMove.post(tap: .cgSessionEventTap)
            usleep(30_000)
            cgMouseDown.post(tap: .cgSessionEventTap)
            usleep(50_000)
            cgMouseUp.post(tap: .cgSessionEventTap)
            return [
                "strategy": "native-quartz-session",
                "viewportX": String(format: "%.1f", target.viewportCenter.x),
                "viewportY": String(format: "%.1f", target.viewportCenter.y),
                "windowX": String(format: "%.1f", windowPoint.x),
                "windowY": String(format: "%.1f", windowPoint.y),
                "screenX": String(format: "%.1f", screenPoint.x),
                "screenY": String(format: "%.1f", screenPoint.y)
            ]
        }

        let timestamp = ProcessInfo.processInfo.systemUptime
        if let mouseDown = NSEvent.mouseEvent(
            with: .leftMouseDown,
            location: windowPoint,
            modifierFlags: [],
            timestamp: timestamp,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 1
        ), let mouseUp = NSEvent.mouseEvent(
            with: .leftMouseUp,
            location: windowPoint,
            modifierFlags: [],
            timestamp: timestamp + 0.01,
            windowNumber: window.windowNumber,
            context: nil,
            eventNumber: 1,
            clickCount: 1,
            pressure: 0
        ) {
            window.sendEvent(mouseDown)
            window.sendEvent(mouseUp)
            return [
                "strategy": "native-nsevent",
                "viewportX": String(format: "%.1f", target.viewportCenter.x),
                "viewportY": String(format: "%.1f", target.viewportCenter.y),
                "windowX": String(format: "%.1f", windowPoint.x),
                "windowY": String(format: "%.1f", windowPoint.y),
                "screenX": String(format: "%.1f", screenPoint.x),
                "screenY": String(format: "%.1f", screenPoint.y)
            ]
        }

        throw AgentSafariError.nativeInputFailed("Failed to create native mouse events")
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
        return [
            "strategy": "js-click",
            "result": target.description,
            "method": "dom",
            "nativeVerified": "false",
            "fallbackUsed": "false"
        ]
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

    private func blurActiveElementBeforeNativeClick() async throws {
        let script = """
        (() => {
          const active = document.activeElement;
          if (active && typeof active.blur === 'function') active.blur();
          return true;
        })()
        """
        _ = try await webView.evaluateJavaScript(script)
    }

    func click(selector: String, native: Bool = false, fallbackPolicy: String = "js") async throws -> [String: String] {
        if native {
            do {
                let target = try await elementHitTarget(selector: selector)
                let token = UUID().uuidString
                try await armNativeClickProbe(selector: selector, token: token)
                let beforeURL = webView.url?.absoluteString ?? ""
                try await blurActiveElementBeforeNativeClick()
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
                        result["method"] = "native"
                        result["nativeVerified"] = "true"
                        result["fallbackUsed"] = "false"
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
                    result["method"] = "native"
                    result["nativeVerified"] = "true"
                    result["fallbackUsed"] = "false"
                    return result
                }
                let afterURL = webView.url?.absoluteString ?? ""
                if webView.isLoading || afterURL != beforeURL {
                    result["selector"] = selector
                    result["result"] = target.description
                    result["strategy"] = "native-quartz-navigation-assumed"
                    result["method"] = "native"
                    result["nativeVerified"] = "true"
                    result["fallbackUsed"] = "false"
                    result["beforeURL"] = beforeURL
                    result["afterURL"] = afterURL
                    return result
                }
                if fallbackPolicy == "none" {
                    throw AgentSafariError.nativeInputFailed("Native Quartz click posted but no DOM click event was observed")
                }
                var fallback = try await javaScriptClick(selector: selector)
                fallback["selector"] = selector
                fallback["strategy"] = "native-unobserved-js-click"
                fallback["method"] = "dom-fallback"
                fallback["nativeVerified"] = "false"
                fallback["fallbackUsed"] = "true"
                fallback["nativeError"] = "Native Quartz click posted but no DOM click event was observed"
                return fallback
            } catch {
                if fallbackPolicy == "none" {
                    throw error
                }
                var fallback = try await javaScriptClick(selector: selector)
                fallback["selector"] = selector
                fallback["strategy"] = "native-failed-js-click"
                fallback["method"] = "dom-fallback"
                fallback["nativeVerified"] = "false"
                fallback["fallbackUsed"] = "true"
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
}
