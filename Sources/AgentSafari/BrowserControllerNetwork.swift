import AgentSafariCore
import AppKit
import Foundation
import WebKit

@MainActor
extension BrowserController {
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
        _ = try await webView.evaluateJavaScript("window.__agentSafariNetworkCaptureEnabled = false; true")
        return ["capturing": "false", "events": list["events"] ?? "[]", "count": list["count"] ?? "0"]
    }

    func networkExport(path: String, maxEntries: Int? = nil, bodyPreviewBytes: Int? = nil) async throws -> [String: String] {
        let maxEntriesLiteral = maxEntries.map(String.init) ?? "null"
        let bodyPreviewLiteral = bodyPreviewBytes.map(String.init) ?? "null"
        let script = """
        (() => {
          const redactNames = new Set(['authorization','cookie','set-cookie','x-api-' + 'key','x-auth-' + 'token','proxy-authorization']);
          const maxEntries = \(maxEntriesLiteral);
          const bodyPreviewBytes = \(bodyPreviewLiteral);
          const redactHeaders = (headers) => {
            const out = {};
            for (const [key, value] of Object.entries(headers || {})) {
              out[key] = redactNames.has(String(key).toLowerCase()) ? '[REDACTED]' : value;
            }
            return out;
          };
          const trimBody = (value) => typeof value === 'string' && bodyPreviewBytes !== null ? value.slice(0, Math.max(0, bodyPreviewBytes)) : value;
          let events = (window.__agentSafariNetworkEvents || []).slice();
          if (maxEntries !== null) events = events.slice(-Math.max(0, maxEntries));
          events = events.map((event) => Object.assign({}, event, {
            requestHeaders: redactHeaders(event.requestHeaders),
            responseHeaders: redactHeaders(event.responseHeaders),
            requestBodyPreview: trimBody(event.requestBodyPreview)
          }));
          var resourceTimings = [];
          try {
            resourceTimings = (performance.getEntriesByType('resource') || []).map((resource) => ({
              type: 'resource-timing',
              phase: 'complete',
              initiatorType: resource.initiatorType || '',
              method: 'GET',
              url: resource.name || '',
              responseURL: resource.name || '',
              status: 0,
              statusText: 'resource-timing',
              startedAt: resource.startTime || 0,
              endedAt: (resource.startTime || 0) + (resource.duration || 0),
              durationMs: Math.round((resource.duration || 0) * 1000) / 1000,
              transferSize: resource.transferSize || 0,
              encodedBodySize: resource.encodedBodySize || 0,
              decodedBodySize: resource.decodedBodySize || 0,
              requestHeaders: {},
              responseHeaders: {},
              wallTime: new Date(Date.now() - Math.max(0, performance.now() - (resource.startTime || 0))).toISOString(),
              source: 'performance-resource-timing'
            })).filter((resource) => resource.url && !events.some((event) => (event.responseURL || event.url) === resource.url));
          } catch (_) {}
          const entries = events.map((event) => ({
            startedDateTime: event.wallTime || new Date().toISOString(),
            time: typeof event.durationMs === 'number' ? event.durationMs : 0,
            request: {
              method: event.method || 'GET',
              url: event.url || event.responseURL || '',
              httpVersion: 'HTTP/2',
              headers: Object.entries(event.requestHeaders || {}).map(([name, value]) => ({ name, value: String(value) })),
              queryString: [],
              cookies: [],
              headersSize: -1,
              bodySize: event.requestBodyPreview ? String(event.requestBodyPreview).length : 0,
              postData: event.requestBodyPreview ? { mimeType: '', text: String(event.requestBodyPreview) } : undefined
            },
            response: {
              status: event.status || 0,
              statusText: event.statusText || event.phase || '',
              httpVersion: 'HTTP/2',
              headers: Object.entries(event.responseHeaders || {}).map(([name, value]) => ({ name, value: String(value) })),
              cookies: [],
              content: { size: -1, mimeType: (event.responseHeaders && event.responseHeaders['content-type']) || '' },
              redirectURL: '',
              headersSize: -1,
              bodySize: -1
            },
            cache: {},
            timings: { send: 0, wait: typeof event.durationMs === 'number' ? event.durationMs : 0, receive: 0 },
            _agentSafari: event
          })).concat(resourceTimings.map((resource) => ({
            startedDateTime: resource.wallTime || new Date().toISOString(),
            time: typeof resource.durationMs === 'number' ? resource.durationMs : 0,
            request: {
              method: 'GET',
              url: resource.url || '',
              httpVersion: 'HTTP/2',
              headers: [],
              queryString: [],
              cookies: [],
              headersSize: -1,
              bodySize: 0
            },
            response: {
              status: 0,
              statusText: 'resource-timing',
              httpVersion: 'HTTP/2',
              headers: [],
              cookies: [],
              content: { size: resource.encodedBodySize || resource.transferSize || -1, mimeType: '' },
              redirectURL: '',
              headersSize: -1,
              bodySize: resource.transferSize || -1
            },
            cache: {},
            timings: { send: 0, wait: typeof resource.durationMs === 'number' ? resource.durationMs : 0, receive: 0 },
            _agentSafari: resource
          })));
          const artifact = {
            log: {
              version: '1.2',
              creator: { name: 'agent-safari', version: '\(AgentSafariMetadata.version)' },
              pages: [{ startedDateTime: new Date().toISOString(), id: 'page_1', title: document.title || '', pageTimings: {} }],
              entries
            },
            agentSafari: {
              schemaVersion: 1,
              captureType: 'fetch-xhr-js-instrumentation',
              limitations: ['fetch/xhr has request/response metadata', 'parser-driven resources are included from PerformanceResourceTiming only', 'no request/response headers for parser-driven resources', 'no websocket frames', 'no service-worker internals'],
              redacted: true,
              eventCount: events.length,
              resourceTimingCount: resourceTimings.length
            }
          };
          return JSON.stringify(artifact, null, 2);
        })()
        """
        let value = try await webView.evaluateJavaScript(script)
        let json = stringifyJavaScriptValue(value as Any)
        let url = URL(fileURLWithPath: path)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try json.write(to: url, atomically: true, encoding: .utf8)
        let countValue = JSONValue.parseJSONText(json)
        let count: Int
        if case .object(let object) = countValue,
           case .object(let log)? = object["log"],
           case .array(let entries)? = log["entries"] {
            count = entries.count
        } else if case .array(let events) = countValue {
            count = events.count
        } else {
            count = 0
        }
        return ["path": url.path, "count": String(count), "redacted": "true", "schema": "har-like", "schemaVersion": "1"]
    }

    private func networkCapturingString() async throws -> String {
        let value = try await webView.evaluateJavaScript("window.__agentSafariNetworkCaptureEnabled === true")
        return stringifyJavaScriptValue(value as Any)
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
}
