import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
    func consoleStart() async throws -> [String: String] {
        let script = BrowserController.consoleInstrumentationScript
        if !consoleUserScriptInstalled {
            let userScript = WKUserScript(source: script + "\nwindow.__agentSafariConsoleCaptureEnabled = true;", injectionTime: .atDocumentStart, forMainFrameOnly: false)
            webView.configuration.userContentController.addUserScript(userScript)
            consoleUserScriptInstalled = true
        }
        consoleCaptureActive = true
        _ = try await webView.evaluateJavaScript(script)
        _ = try await webView.evaluateJavaScript("window.__agentSafariConsoleCaptureEnabled = true; if (window.__agentSafariConsoleEvents) window.__agentSafariConsoleEvents.length = 0; true")
        return ["capturing": "true", "events": "[]", "count": "0"]
    }

    func consoleList() async throws -> [String: String] {
        let value = try await webView.evaluateJavaScript("JSON.stringify(window.__agentSafariConsoleEvents || [])")
        let events = stringifyJavaScriptValue(value as Any)
        let countValue = try await webView.evaluateJavaScript("(window.__agentSafariConsoleEvents || []).length")
        return ["capturing": consoleCaptureActive ? "true" : "false", "events": events, "count": stringifyJavaScriptValue(countValue as Any)]
    }

    func consoleStop() async throws -> [String: String] {
        let list = try await consoleList()
        consoleCaptureActive = false
        _ = try await webView.evaluateJavaScript("window.__agentSafariConsoleCaptureEnabled = false; true")
        return ["capturing": "false", "events": list["events"] ?? "[]", "count": list["count"] ?? "0"]
    }

    private static let consoleInstrumentationScript = """
    (function installAgentSafariConsoleCapture(global) {
      'use strict';
      if (!global) return;
      global.__agentSafariConsoleEvents = global.__agentSafariConsoleEvents || [];
      global.__agentSafariConsoleCaptureEnabled = global.__agentSafariConsoleCaptureEnabled === true;
      if (global.__agentSafariConsoleCaptureInstalled) return;
      var MAX_ENTRIES = 200;
      function ts() { return new Date().toISOString(); }
      function stringify(args) {
        return Array.prototype.slice.call(args).map(function(a) {
          if (a === null) return 'null';
          if (a === undefined) return 'undefined';
          if (typeof a === 'string') return a;
          try { return JSON.stringify(a); } catch (_) { return String(a); }
        }).join(' ');
      }
      function push(entry) {
        if (!global.__agentSafariConsoleCaptureEnabled) return;
        global.__agentSafariConsoleEvents.push(entry);
        if (global.__agentSafariConsoleEvents.length > MAX_ENTRIES) global.__agentSafariConsoleEvents.splice(0, global.__agentSafariConsoleEvents.length - MAX_ENTRIES);
      }
      global.__agentSafariConsoleCaptureInstalled = true;
      var originalError = global.console && global.console.error;
      var originalWarn = global.console && global.console.warn;
      try {
        if (global.console && typeof originalError === 'function') {
          global.console.error = function() {
            push({ type: 'console', level: 'error', message: stringify(arguments), source: '', line: 0, ts: ts() });
            return originalError.apply(global.console, arguments);
          };
        }
      } catch (_) {}
      try {
        if (global.console && typeof originalWarn === 'function') {
          global.console.warn = function() {
            push({ type: 'console', level: 'warn', message: stringify(arguments), source: '', line: 0, ts: ts() });
            return originalWarn.apply(global.console, arguments);
          };
        }
      } catch (_) {}
      try {
        global.addEventListener('error', function(event) {
          push({ type: 'error', level: 'error', message: event.message || String(event), source: event.filename || '', line: event.lineno || 0, ts: ts() });
        });
      } catch (_) {}
      try {
        global.addEventListener('unhandledrejection', function(event) {
          var reason = event.reason;
          var msg;
          try { msg = reason instanceof Error ? (reason.message || String(reason)) : JSON.stringify(reason); } catch (_) { msg = String(reason); }
          push({ type: 'unhandledrejection', level: 'error', message: msg, source: '', line: 0, ts: ts() });
        });
      } catch (_) {}
    })(typeof window !== 'undefined' ? window : this);
    """
}
