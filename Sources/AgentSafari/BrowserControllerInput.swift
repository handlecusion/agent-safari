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
          const fail = (code, message) => ({ ok: false, code, message });
          const isFailure = (value) => value && value.ok === false;
          const resolveElement = (target) => {
            if (target.startsWith('@e')) {
              const refs = window.__agentSafariSnapshotRefs;
              if (!refs || typeof refs.get !== 'function') {
                return fail('actionability_refs_unavailable', `Snapshot refs are not available for ${target}; run snapshot first.`);
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
              return fail('actionability_stale_ref', `No element found for snapshot ref: ${target}. Run snapshot first or refresh it with snapshot.`);
            }

            const element = document.querySelector(target);
            if (!element) {
              return fail('actionability_missing_selector', `No element found for selector: ${target}`);
            }
            return element;
          };

          const validateActionableElement = (element, target) => {
            if (element.disabled || element.getAttribute('aria-disabled') === 'true') {
              return fail('actionability_disabled', `Element is disabled: ${target}`);
            }
            const rect = element.getBoundingClientRect();
            const style = window.getComputedStyle(element);
            if (!rect || rect.width <= 0 || rect.height <= 0 || style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity || '1') <= 0) {
              return fail('actionability_hidden', `Element is hidden: ${target}`);
            }
            const centerX = rect.left + rect.width / 2;
            const centerY = rect.top + rect.height / 2;
            if (centerX < 0 || centerY < 0 || centerX > window.innerWidth || centerY > window.innerHeight) {
              return fail('actionability_off_viewport', `Element center is outside viewport: ${target}`);
            }
            return rect;
          };

          const element = resolveElement(target);
          if (isFailure(element)) return element;
          const scrollXBefore = window.scrollX;
          const scrollYBefore = window.scrollY;
          element.scrollIntoView({ block: 'center', inline: 'center' });
          const actionableRect = validateActionableElement(element, target);
          if (isFailure(actionableRect)) return actionableRect;
          const rect = element.getBoundingClientRect();
          const centerX = rect.left + rect.width / 2;
          const centerY = rect.top + rect.height / 2;
          const centerHit = document.elementFromPoint(
            Math.min(Math.max(centerX, 0), window.innerWidth - 1),
            Math.min(Math.max(centerY, 0), window.innerHeight - 1)
          );
          if (centerHit && centerHit !== element && !element.contains(centerHit)) {
            const hitName = `${centerHit.tagName || ''}${centerHit.id ? '#' + centerHit.id : ''}`;
            return fail('actionability_occluded', `Element center is occluded: ${target}; hit ${hitName}`);
          }
          return {
            ok: true,
            x: rect.left,
            y: rect.top,
            width: rect.width,
            height: rect.height,
            centerX,
            centerY,
            viewportWidth: window.innerWidth,
            viewportHeight: window.innerHeight,
            scrollXBefore,
            scrollYBefore,
            scrollXAfter: window.scrollX,
            scrollYAfter: window.scrollY,
            description: `clicked ${element.tagName || ''}${element.id ? '#' + element.id : ''}`
          };
        })()
        """
        guard let result = try await webView.evaluateJavaScript(script) as? [String: Any] else {
            throw AgentSafariError.elementResolutionFailed(selector)
        }
        try throwActionabilityFailureIfPresent(result)
        let x = CGFloat((result["x"] as? NSNumber)?.doubleValue ?? 0)
        let y = CGFloat((result["y"] as? NSNumber)?.doubleValue ?? 0)
        let width = CGFloat((result["width"] as? NSNumber)?.doubleValue ?? 0)
        let height = CGFloat((result["height"] as? NSNumber)?.doubleValue ?? 0)
        let centerX = CGFloat((result["centerX"] as? NSNumber)?.doubleValue ?? 0)
        let centerY = CGFloat((result["centerY"] as? NSNumber)?.doubleValue ?? 0)
        let viewportWidth = CGFloat((result["viewportWidth"] as? NSNumber)?.doubleValue ?? 0)
        let viewportHeight = CGFloat((result["viewportHeight"] as? NSNumber)?.doubleValue ?? 0)
        let scrollXBefore = CGFloat((result["scrollXBefore"] as? NSNumber)?.doubleValue ?? 0)
        let scrollYBefore = CGFloat((result["scrollYBefore"] as? NSNumber)?.doubleValue ?? 0)
        let scrollXAfter = CGFloat((result["scrollXAfter"] as? NSNumber)?.doubleValue ?? 0)
        let scrollYAfter = CGFloat((result["scrollYAfter"] as? NSNumber)?.doubleValue ?? 0)
        guard width > 0, height > 0 else { throw AgentSafariError.elementResolutionFailed(selector) }
        return ElementHitTarget(
            viewportCenter: CGPoint(x: centerX, y: centerY),
            viewportBounds: CGRect(x: x, y: y, width: width, height: height),
            viewportSize: CGSize(width: viewportWidth, height: viewportHeight),
            scrollBefore: CGPoint(x: scrollXBefore, y: scrollYBefore),
            scrollAfter: CGPoint(x: scrollXAfter, y: scrollYAfter),
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
            var result = target.resultFields
            result.merge([
                "strategy": "native-quartz-session",
                "coordinateStrategy": "webkit-viewport-to-window-to-quartz",
                "windowX": String(format: "%.1f", windowPoint.x),
                "windowY": String(format: "%.1f", windowPoint.y),
                "screenX": String(format: "%.1f", screenPoint.x),
                "screenY": String(format: "%.1f", screenPoint.y)
            ]) { _, new in new }
            return result
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
            var result = target.resultFields
            result.merge([
                "strategy": "native-nsevent",
                "coordinateStrategy": "webkit-viewport-to-window-nsevent",
                "windowX": String(format: "%.1f", windowPoint.x),
                "windowY": String(format: "%.1f", windowPoint.y),
                "screenX": String(format: "%.1f", screenPoint.x),
                "screenY": String(format: "%.1f", screenPoint.y)
            ]) { _, new in new }
            return result
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
          const anchor = typeof element.closest === 'function' ? element.closest('a[target]') : null;
          const anchorTarget = anchor ? anchor.getAttribute('target') : null;
          const popupExpected = !!anchorTarget && !['_self', '_parent', '_top'].includes(anchorTarget);
          // A click on a cross-document anchor (or one with a download attribute) can become
          // a download whose callback arrives after a navigation round-trip. Same-document
          // fragment links and in-page buttons never do, so they skip the longer wait.
          const navAnchor = typeof element.closest === 'function' ? element.closest('a[href],a[download]') : null;
          let navigationLikely = false;
          if (navAnchor) {
            if (navAnchor.hasAttribute('download')) {
              navigationLikely = true;
            } else {
              try {
                const dest = new URL(navAnchor.href, document.baseURI);
                const here = new URL(document.URL);
                const sameDocument = dest.origin === here.origin && dest.pathname === here.pathname && dest.search === here.search;
                const downloadableScheme = ['http:', 'https:', 'file:', 'data:', 'blob:'].includes(dest.protocol);
                navigationLikely = downloadableScheme && !sameDocument;
              } catch (_) {
                navigationLikely = false;
              }
            }
          }
          element.click();
          return { popupExpected, navigationLikely };
        })()
        """
        let clickInfo = (try await webView.evaluateJavaScript(script) as? [String: Any]) ?? [:]
        let popupExpected = (clickInfo["popupExpected"] as? Bool) ?? false
        let navigationLikely = (clickInfo["navigationLikely"] as? Bool) ?? false
        await settlePendingPopupRedirect(expected: popupExpected)
        if navigationLikely { await settlePendingDownload() }
        var result = target.resultFields
        result.merge([
            "strategy": "js-click",
            "coordinateStrategy": "dom-scroll-then-click",
            "result": target.description,
            "method": "dom",
            "nativeVerified": "false",
            "fallbackUsed": "false"
        ]) { _, new in new }
        return result
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

    // WebKit delivers createWebViewWith asynchronously for anchor-driven popups; give it a
    // bounded window so the redirect is reported on the click that caused it.
    private func settlePendingPopupRedirect(expected: Bool) async {
        guard expected, pendingPopupRedirectURL == nil else { return }
        for _ in 0..<12 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if pendingPopupRedirectURL != nil { return }
        }
    }

    // WebKit decides downloads asynchronously after a cross-document anchor click; give it a
    // bounded window so a download triggered by this click is reported on the click that
    // caused it, returning as soon as the evidence arrives (the common case settles in well
    // under this window). Only called when the click could navigate (cross-document anchor or
    // a download attribute), so plain buttons and same-document links stay fast. `downloads` /
    // `wait-for-download` remain the authoritative confirmation regardless.
    private func settlePendingDownload() async {
        guard pendingDownloadStarted == nil else { return }
        for _ in 0..<50 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if pendingDownloadStarted != nil { return }
        }
    }

    func click(selector: String, native: Bool = false, fallbackPolicy: String = "js") async throws -> [String: String] {
        // Discard popup/download evidence from earlier actions so it cannot attach to this click.
        pendingPopupRedirectURL = nil
        pendingDownloadStarted = nil
        if native {
            // Quartz events land on the visible tab; refuse rather than click the wrong page.
            guard webView === activeTabWebView else {
                throw AgentSafariError.tabNotActiveForNativeInput(TabTarget.tabID ?? activeTabID)
            }
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
                        let nativeError = "Probe failed during navigation: \(describeError(error))"
                        result["nativeError"] = nativeError
                        result["nativeErrorCode"] = agentSafariErrorCode(nativeError)
                        if let u = pendingPopupRedirectURL { result["popupRedirectedURL"] = u; pendingPopupRedirectURL = nil }
                        if let d = pendingDownloadStarted { result["downloadStarted"] = "true"; result["downloadId"] = d; pendingDownloadStarted = nil }
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
                    if let u = pendingPopupRedirectURL { result["popupRedirectedURL"] = u; pendingPopupRedirectURL = nil }
                    if let d = pendingDownloadStarted { result["downloadStarted"] = "true"; result["downloadId"] = d; pendingDownloadStarted = nil }
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
                    if let u = pendingPopupRedirectURL { result["popupRedirectedURL"] = u; pendingPopupRedirectURL = nil }
                    if let d = pendingDownloadStarted { result["downloadStarted"] = "true"; result["downloadId"] = d; pendingDownloadStarted = nil }
                    return result
                }
                if fallbackPolicy == "none" {
                    throw AgentSafariError.nativeClickUnverified("Native Quartz click posted but no DOM click event was observed")
                }
                var fallback = try await javaScriptClick(selector: selector)
                fallback["selector"] = selector
                fallback["strategy"] = "native-unobserved-js-click"
                fallback["method"] = "dom-fallback"
                fallback["nativeVerified"] = "false"
                fallback["fallbackUsed"] = "true"
                fallback["nativeError"] = "Native Quartz click posted but no DOM click event was observed"
                fallback["nativeErrorCode"] = "native_click_unverified"
                fallback.merge(target.resultFields) { current, _ in current }
                if let u = pendingPopupRedirectURL { fallback["popupRedirectedURL"] = u; pendingPopupRedirectURL = nil }
                if let d = pendingDownloadStarted { fallback["downloadStarted"] = "true"; fallback["downloadId"] = d; pendingDownloadStarted = nil }
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
                let nativeError = describeError(error)
                fallback["nativeError"] = nativeError
                fallback["nativeErrorCode"] = agentSafariErrorCode(nativeError)
                if let u = pendingPopupRedirectURL { fallback["popupRedirectedURL"] = u; pendingPopupRedirectURL = nil }
                if let d = pendingDownloadStarted { fallback["downloadStarted"] = "true"; fallback["downloadId"] = d; pendingDownloadStarted = nil }
                return fallback
            }
        }

        var result = try await javaScriptClick(selector: selector)
        result["selector"] = selector
        if let u = pendingPopupRedirectURL { result["popupRedirectedURL"] = u; pendingPopupRedirectURL = nil }
        if let d = pendingDownloadStarted { result["downloadStarted"] = "true"; result["downloadId"] = d; pendingDownloadStarted = nil }
        return result
    }

    func fill(selector: String, value: String) async throws -> [String: String] {
        let selectorLiteral = try javaScriptStringLiteral(selector)
        let valueLiteral = try javaScriptStringLiteral(value)
        let script = """
        (() => {
          const target = \(selectorLiteral);
          const value = \(valueLiteral);
          const fail = (code, message) => ({ ok: false, code, message });
          const isFailure = (value) => value && value.ok === false;
          const resolveElement = (target) => {
            if (target.startsWith('@e')) {
              const refs = window.__agentSafariSnapshotRefs;
              if (!refs || typeof refs.get !== 'function') {
                return fail('actionability_refs_unavailable', `Snapshot refs are not available for ${target}; run snapshot first.`);
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
              return fail('actionability_stale_ref', `No element found for snapshot ref: ${target}. Run snapshot first or refresh it with snapshot.`);
            }

            const element = document.querySelector(target);
            if (!element) {
              return fail('actionability_missing_selector', `No element found for selector: ${target}`);
            }
            return element;
          };

          const validateActionableElement = (element, target) => {
            if (element.disabled || element.getAttribute('aria-disabled') === 'true') {
              return fail('actionability_disabled', `Element is disabled: ${target}`);
            }
            const rect = element.getBoundingClientRect();
            const style = window.getComputedStyle(element);
            if (!rect || rect.width <= 0 || rect.height <= 0 || style.display === 'none' || style.visibility === 'hidden' || Number(style.opacity || '1') <= 0) {
              return fail('actionability_hidden', `Element is hidden: ${target}`);
            }
            const centerX = rect.left + rect.width / 2;
            const centerY = rect.top + rect.height / 2;
            if (centerX < 0 || centerY < 0 || centerX > window.innerWidth || centerY > window.innerHeight) {
              return fail('actionability_off_viewport', `Element center is outside viewport: ${target}`);
            }
            return { ok: true };
          };

          const element = resolveElement(target);
          if (isFailure(element)) return element;
          element.scrollIntoView({ block: 'center', inline: 'center' });
          const actionability = validateActionableElement(element, target);
          if (isFailure(actionability)) return actionability;
          if (typeof element.focus === 'function') element.focus({ preventScroll: true });
          element.value = value;
          element.dispatchEvent(new Event('input', { bubbles: true }));
          element.dispatchEvent(new Event('change', { bubbles: true }));
          return { ok: true, value: element.value || '' };
        })()
        """
        guard let result = try await webView.evaluateJavaScript(script) as? [String: Any] else {
            throw AgentSafariError.elementResolutionFailed(selector)
        }
        try throwActionabilityFailureIfPresent(result)
        return ["selector": selector, "value": stringifyJavaScriptValue(result["value"] as Any)]
    }

    func key(_ key: String) async throws -> [String: String] {
        let keyLiteral = try javaScriptStringLiteral(key)
        let script = """
        (() => {
          const keySpec = \(keyLiteral);
          const target = document.activeElement || document.body;
          if (!target) throw new Error('No active element for key dispatch');

          const parseKeySpec = (spec) => {
            const parts = String(spec).split('+').map(part => part.trim()).filter(Boolean);
            const key = parts.pop() || spec;
            const modifiers = new Set(parts.map(part => part.toLowerCase()));
            return {
              key,
              altKey: modifiers.has('alt') || modifiers.has('option'),
              ctrlKey: modifiers.has('ctrl') || modifiers.has('control'),
              metaKey: modifiers.has('cmd') || modifiers.has('command') || modifiers.has('meta'),
              shiftKey: modifiers.has('shift')
            };
          };

          const editableState = (element) => {
            if (!element) return null;
            if (element.isContentEditable) {
              const selection = window.getSelection();
              return { kind: 'contenteditable', element, selection };
            }
            const tag = (element.tagName || '').toLowerCase();
            if (tag === 'input' || tag === 'textarea') {
              return {
                kind: tag,
                element,
                value: String(element.value || ''),
                start: Number.isFinite(element.selectionStart) ? element.selectionStart : String(element.value || '').length,
                end: Number.isFinite(element.selectionEnd) ? element.selectionEnd : String(element.value || '').length
              };
            }
            return null;
          };

          const dispatchInput = (element, inputType, data = null) => {
            element.dispatchEvent(new InputEvent('input', { bubbles: true, cancelable: true, data, inputType }));
            element.dispatchEvent(new Event('change', { bubbles: true }));
          };

          function selectAllEditableText(state) {
            if (!state) return false;
            if (state.kind === 'input' || state.kind === 'textarea') {
              state.element.setSelectionRange(0, String(state.element.value || '').length);
              return true;
            }
            if (state.kind === 'contenteditable') {
              const range = document.createRange();
              range.selectNodeContents(state.element);
              const selection = window.getSelection();
              selection.removeAllRanges();
              selection.addRange(range);
              return true;
            }
            return false;
          }

          function editTextTarget(state, normalizedKey) {
            if (!state) return { edited: false, mode: 'none' };
            if (state.kind === 'contenteditable') {
              switch (normalizedKey) {
                case 'Backspace':
                  document.execCommand('delete', false, null);
                  dispatchInput(state.element, 'deleteContentBackward');
                  return { edited: true, mode: 'contenteditable-deleteBackward', value: state.element.textContent || '' };
                case 'Delete':
                  document.execCommand('forwardDelete', false, null);
                  dispatchInput(state.element, 'deleteContentForward');
                  return { edited: true, mode: 'contenteditable-deleteForward', value: state.element.textContent || '' };
                case 'Enter':
                  document.execCommand('insertLineBreak', false, null);
                  dispatchInput(state.element, 'insertLineBreak', '\\n');
                  return { edited: true, mode: 'contenteditable-insertLineBreak', value: state.element.textContent || '' };
                case 'ArrowLeft':
                case 'ArrowRight':
                case 'ArrowUp':
                case 'ArrowDown':
                  return { edited: false, mode: 'contenteditable-navigation', value: state.element.textContent || '' };
                default:
                  return { edited: false, mode: 'contenteditable-unhandled', value: state.element.textContent || '' };
              }
            }

            const element = state.element;
            const value = String(element.value || '');
            let start = state.start;
            let end = state.end;
            const replaceRange = (nextValue, cursor, inputType, data = null) => {
              element.value = nextValue;
              if (typeof element.setSelectionRange === 'function') element.setSelectionRange(cursor, cursor);
              dispatchInput(element, inputType, data);
              return { edited: true, mode: inputType, value: element.value || '' };
            };

            switch (normalizedKey) {
              case 'Backspace': {
                if (start === end && start > 0) start -= 1;
                return replaceRange(value.slice(0, start) + value.slice(end), start, 'deleteContentBackward');
              }
              case 'Delete': {
                if (start === end && end < value.length) end += 1;
                return replaceRange(value.slice(0, start) + value.slice(end), start, 'deleteContentForward');
              }
              case 'Enter': {
                if (state.kind !== 'textarea') return { edited: false, mode: 'enter-non-textarea', value: element.value || '' };
                return replaceRange(value.slice(0, start) + '\\n' + value.slice(end), start + 1, 'insertLineBreak', '\\n');
              }
              case 'ArrowLeft': {
                const cursor = Math.max(0, start - 1);
                if (typeof element.setSelectionRange === 'function') element.setSelectionRange(cursor, cursor);
                return { edited: false, mode: 'move-left', value: element.value || '' };
              }
              case 'ArrowRight': {
                const cursor = Math.min(value.length, end + 1);
                if (typeof element.setSelectionRange === 'function') element.setSelectionRange(cursor, cursor);
                return { edited: false, mode: 'move-right', value: element.value || '' };
              }
              default:
                return { edited: false, mode: 'unhandled', value: element.value || '' };
            }
          }

          const parsed = parseKeySpec(keySpec);
          const normalizedKey = parsed.key;
          let defaultPrevented = false;
          for (const type of ['keydown', 'keypress', 'keyup']) {
            const event = new KeyboardEvent(type, { key: normalizedKey, bubbles: true, cancelable: true, altKey: parsed.altKey, ctrlKey: parsed.ctrlKey, metaKey: parsed.metaKey, shiftKey: parsed.shiftKey });
            target.dispatchEvent(event);
            defaultPrevented = defaultPrevented || event.defaultPrevented;
          }

          const state = editableState(target);
          let edit = { edited: false, mode: 'event-only' };
          if ((parsed.metaKey || parsed.ctrlKey) && normalizedKey.toLowerCase() === 'a') {
            edit = { edited: selectAllEditableText(state), mode: 'select-all', value: state?.element?.value || state?.element?.textContent || '' };
          } else {
            edit = editTextTarget(state, normalizedKey);
          }

          return { key: normalizedKey, keySpec, target: (target && target.tagName) || '', defaultPrevented, mode: edit.mode || '', edited: !!edit.edited, value: edit.value || '', metaKey: parsed.metaKey, ctrlKey: parsed.ctrlKey, altKey: parsed.altKey, shiftKey: parsed.shiftKey };
        })()
        """
        guard let result = try await webView.evaluateJavaScript(script) as? [String: Any] else {
            return ["key": key, "strategy": "synthetic-key"]
        }
        return [
            "key": stringifyJavaScriptValue(result["key"] as Any),
            "keySpec": stringifyJavaScriptValue(result["keySpec"] as Any),
            "target": stringifyJavaScriptValue(result["target"] as Any),
            "defaultPrevented": stringifyJavaScriptValue(result["defaultPrevented"] as Any),
            "mode": stringifyJavaScriptValue(result["mode"] as Any),
            "edited": stringifyJavaScriptValue(result["edited"] as Any),
            "value": stringifyJavaScriptValue(result["value"] as Any),
            "metaKey": stringifyJavaScriptValue(result["metaKey"] as Any),
            "ctrlKey": stringifyJavaScriptValue(result["ctrlKey"] as Any),
            "altKey": stringifyJavaScriptValue(result["altKey"] as Any),
            "shiftKey": stringifyJavaScriptValue(result["shiftKey"] as Any),
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
