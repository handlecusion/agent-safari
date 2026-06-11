import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    /// Reuses the resolveElement JS pattern from input so a CSS selector or a
    /// snapshot `@e` ref resolves to the same element with the same
    /// actionability_* failure codes. Validates the element is an
    /// <video>/<audio> media element so callers get a precise failure.
    private func mediaResolveElementJS(target literal: String) -> String {
        """
        const target = \(literal);
        const fail = (code, message) => ({ ok: false, code, message });
        const isFailure = (value) => value && value.ok === false;
        const refs = window.__agentSafariSnapshotRefs;
        const resolveElement = (target) => {
          if (target.startsWith('@e')) {
            if (!refs || typeof refs.get !== 'function') {
              return fail('actionability_refs_unavailable', `Snapshot refs are not available for ${target}; run snapshot first.`);
            }
            const candidates = [...document.querySelectorAll('video,audio,a,button,input,select,textarea,summary,label,[role],[onclick],[tabindex],[contenteditable]'), ...document.querySelectorAll('*')];
            const seen = new Set();
            for (const element of candidates) {
              if (seen.has(element)) continue;
              seen.add(element);
              if (refs.get(element) === target) return element;
            }
            return fail('actionability_stale_ref', `No element found for snapshot ref: ${target}. Run snapshot first or refresh it with snapshot.`);
          }
          const element = document.querySelector(target);
          if (!element) return fail('actionability_missing_selector', `No element found for selector: ${target}`);
          return element;
        };
        const isMedia = (element) => element instanceof HTMLMediaElement;
        """
    }

    /// Read-only inventory of every <video>/<audio> element on the page. NaN/Infinity
    /// durations are normalized to -1 ("unknown"), which the docs document, so the
    /// JSON round-trips cleanly (JSON has no NaN literal).
    func media() async throws -> [String: String] {
        let script = """
        (() => {
          const numberOrUnknown = (value) => (typeof value === 'number' && isFinite(value)) ? value : -1;
          const elements = Array.from(document.querySelectorAll('video, audio'));
          const inventory = elements.map((element, index) => ({
            index,
            tag: (element.tagName || '').toLowerCase(),
            id: element.id || '',
            currentSrc: element.currentSrc || '',
            duration: numberOrUnknown(element.duration),
            paused: !!element.paused,
            ended: !!element.ended,
            muted: !!element.muted,
            volume: numberOrUnknown(element.volume),
            currentTime: numberOrUnknown(element.currentTime),
            readyState: element.readyState,
            videoWidth: element.tagName === 'VIDEO' ? element.videoWidth : 0,
            videoHeight: element.tagName === 'VIDEO' ? element.videoHeight : 0,
            poster: element.tagName === 'VIDEO' ? (element.poster || '') : ''
          }));
          return JSON.stringify(inventory);
        })()
        """
        let value = try await webView.evaluateJavaScript(script)
        return ["elements": stringifyJavaScriptValue(value as Any)]
    }

    /// Polls (mirroring the waits family) until the media element matches a state.
    /// playing: !paused && !ended && readyState >= 2; paused; ended; canplay: readyState >= 3.
    /// Element resolution reuses the resolveElement JS so actionability_* codes stay consistent.
    func waitForMedia(selector: String, state: String, timeoutMs: Int) async throws -> [String: String] {
        let allowedStates = ["playing", "paused", "ended", "canplay"]
        guard allowedStates.contains(state) else {
            throw AgentSafariError.invalidIntegerParam("state", state)
        }
        let selectorLiteral = try javaScriptStringLiteral(selector)
        let stateLiteral = try javaScriptStringLiteral(state)
        let script = """
        (() => {
          \(mediaResolveElementJS(target: selectorLiteral))
          const wantState = \(stateLiteral);
          const element = resolveElement(target);
          if (isFailure(element)) return element;
          if (!isMedia(element)) return fail('element_resolution_failed', `Element is not a media element: ${target}`);
          const matchesState = () => {
            const playing = !element.paused && !element.ended && element.readyState >= 2;
            switch (wantState) {
              case 'playing': return playing;
              case 'paused': return !!element.paused;
              case 'ended': return !!element.ended;
              case 'canplay': return element.readyState >= 3;
              default: return false;
            }
          };
          return { ok: true, matched: matchesState() };
        })()
        """
        let clampedTimeoutMs = max(0, timeoutMs)
        let deadline = Date().addingTimeInterval(Double(clampedTimeoutMs) / 1000.0)
        repeat {
            guard let result = try await webView.evaluateJavaScript(script) as? [String: Any] else {
                throw AgentSafariError.elementResolutionFailed(selector)
            }
            try throwActionabilityFailureIfPresent(result)
            if (result["matched"] as? Bool) == true {
                return ["selector": selector, "state": state, "matched": "true", "timeoutMs": String(clampedTimeoutMs)]
            }
            if Date() >= deadline {
                break
            }
            try await Task.sleep(nanoseconds: 100_000_000)
        } while true
        throw AgentSafariError.waitTimedOut(clampedTimeoutMs)
    }

    /// Drives a media element via JS for play|pause|mute|unmute|seek. play() returns a
    /// Promise, awaited in-page; a rejection (e.g. autoplay policy) is surfaced as the
    /// structured mediaPlayRejected error. seek requires non-negative fractional seconds.
    /// Result carries before/after {paused, currentTime, muted} plus the action.
    func mediaControl(selector: String, action: String, seconds: Double?) async throws -> [String: String] {
        let allowedActions = ["play", "pause", "mute", "unmute", "seek"]
        guard allowedActions.contains(action) else {
            throw AgentSafariError.invalidIntegerParam("action", action)
        }
        if action == "seek", seconds == nil {
            throw AgentSafariError.missingParam("seconds")
        }
        let selectorLiteral = try javaScriptStringLiteral(selector)
        let actionLiteral = try javaScriptStringLiteral(action)
        let secondsLiteral = seconds.map { String($0) } ?? "null"
        let script = """
        return await (async () => {
          \(mediaResolveElementJS(target: selectorLiteral))
          const action = \(actionLiteral);
          const seekSeconds = \(secondsLiteral);
          const element = resolveElement(target);
          if (isFailure(element)) return element;
          if (!isMedia(element)) return fail('element_resolution_failed', `Element is not a media element: ${target}`);
          const snap = () => ({ paused: !!element.paused, currentTime: (typeof element.currentTime === 'number' && isFinite(element.currentTime)) ? element.currentTime : -1, muted: !!element.muted });
          const before = snap();
          if (action === 'play') {
            try {
              const result = element.play();
              if (result && typeof result.then === 'function') {
                // Bound the await: a media element with no playable source returns a
                // play() Promise that never settles, which would hang the daemon command.
                // Race it against a timeout, then fall back to the observed paused state.
                const TIMED_OUT = Symbol('play-timeout');
                const outcome = await Promise.race([
                  result.then(() => 'resolved'),
                  new Promise((resolve) => setTimeout(() => resolve(TIMED_OUT), 3000))
                ]);
                if (outcome === TIMED_OUT && element.paused) {
                  return fail('media_play_rejected', `play() did not start playback within 3000 ms (no playable source?): ${target}`);
                }
              }
            } catch (error) {
              return fail('media_play_rejected', (error && error.message) ? error.message : String(error));
            }
          } else if (action === 'pause') {
            element.pause();
          } else if (action === 'mute') {
            element.muted = true;
          } else if (action === 'unmute') {
            element.muted = false;
          } else if (action === 'seek') {
            element.currentTime = seekSeconds;
          }
          return { ok: true, action, before, after: snap() };
        })()
        """
        guard let result = try await webView.callAsyncJavaScript(script, arguments: [:], contentWorld: .page) as? [String: Any] else {
            throw AgentSafariError.elementResolutionFailed(selector)
        }
        if let ok = result["ok"] as? Bool, ok == false {
            let code = stringifyJavaScriptValue(result["code"] as Any)
            let message = stringifyJavaScriptValue(result["message"] as Any)
            if code == "media_play_rejected" {
                throw AgentSafariError.mediaPlayRejected(message)
            }
            if code.hasPrefix("actionability_") {
                throw AgentSafariError.actionabilityFailed(code: code, message: message)
            }
            throw AgentSafariError.elementResolutionFailed(message.isEmpty ? selector : message)
        }
        let before = result["before"] as? [String: Any] ?? [:]
        let after = result["after"] as? [String: Any] ?? [:]
        // WebKit bridges JS booleans to NSNumber(1/0); emit "true"/"false" so the
        // evidence round-trips to JSON booleans via JSONValue.fromStringMap.
        let boolText = { (value: Any?) in ((value as? NSNumber)?.boolValue ?? false) ? "true" : "false" }
        return [
            "selector": selector,
            "action": action,
            "pausedBefore": boolText(before["paused"]),
            "currentTimeBefore": stringifyJavaScriptValue(before["currentTime"] as Any),
            "mutedBefore": boolText(before["muted"]),
            "pausedAfter": boolText(after["paused"]),
            "currentTimeAfter": stringifyJavaScriptValue(after["currentTime"] as Any),
            "mutedAfter": boolText(after["muted"])
        ]
    }
}
