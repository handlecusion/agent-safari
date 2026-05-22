// Agent Safari network capture instrumentation spike.
// Intended injection point: WKUserScript at .atDocumentStart for every page frame,
// with evaluateJavaScript fallback for the currently loaded document during an MVP.
//
// It records same-page fetch/XMLHttpRequest metadata in window.__agentSafariNetworkLog.
// It does not observe parser-driven resources (<img>, <script>, CSS), WebSocket frames,
// service-worker traffic, downloads, or cross-origin response bodies blocked by CORS.
(function installAgentSafariNetworkCapture(global) {
  'use strict';

  if (!global || global.__agentSafariNetworkCaptureInstalled) {
    return;
  }

  var MAX_BODY_PREVIEW = 4096;
  var MAX_ENTRIES = 1000;
  var originalFetch = global.fetch;
  var OriginalXMLHttpRequest = global.XMLHttpRequest;
  var now = function () {
    if (global.performance && typeof global.performance.now === 'function') {
      return global.performance.now();
    }
    return Date.now();
  };

  function toHeaderObject(headers) {
    var out = {};
    if (!headers) return out;
    try {
      if (typeof headers.forEach === 'function') {
        headers.forEach(function (value, key) { out[String(key).toLowerCase()] = String(value); });
        return out;
      }
      if (Array.isArray(headers)) {
        headers.forEach(function (pair) {
          if (pair && pair.length >= 2) out[String(pair[0]).toLowerCase()] = String(pair[1]);
        });
        return out;
      }
      Object.keys(headers).forEach(function (key) { out[String(key).toLowerCase()] = String(headers[key]); });
    } catch (_) {}
    return out;
  }

  function previewBody(value) {
    if (value == null) return undefined;
    try {
      if (typeof value === 'string') return value.slice(0, MAX_BODY_PREVIEW);
      if (value instanceof URLSearchParams) return value.toString().slice(0, MAX_BODY_PREVIEW);
      if (value instanceof FormData) {
        var fields = [];
        value.forEach(function (fieldValue, key) {
          fields.push([String(key), fieldValue instanceof File ? '[File:' + fieldValue.name + ']' : String(fieldValue)]);
        });
        return JSON.stringify(fields).slice(0, MAX_BODY_PREVIEW);
      }
      if (value instanceof Blob) return '[Blob size=' + value.size + ' type=' + value.type + ']';
      if (value instanceof ArrayBuffer) return '[ArrayBuffer byteLength=' + value.byteLength + ']';
    } catch (_) {}
    return Object.prototype.toString.call(value);
  }

  function push(entry) {
    entry.id = global.__agentSafariNetworkNextId++;
    entry.wallTime = new Date().toISOString();
    global.__agentSafariNetworkLog.push(entry);
    if (global.__agentSafariNetworkLog.length > MAX_ENTRIES) {
      global.__agentSafariNetworkLog.splice(0, global.__agentSafariNetworkLog.length - MAX_ENTRIES);
    }
    return entry;
  }

  global.__agentSafariNetworkCaptureInstalled = true;
  global.__agentSafariNetworkLog = global.__agentSafariNetworkLog || [];
  global.__agentSafariNetworkNextId = global.__agentSafariNetworkNextId || 1;
  global.__agentSafariNetwork = {
    list: function () { return global.__agentSafariNetworkLog.slice(); },
    clear: function () { global.__agentSafariNetworkLog.length = 0; return true; },
    export: function () { return JSON.stringify(global.__agentSafariNetworkLog, null, 2); }
  };

  if (typeof originalFetch === 'function') {
    global.fetch = function agentSafariFetch(input, init) {
      var request;
      var url = '';
      var method = 'GET';
      var requestHeaders = {};
      var requestBodyPreview;
      try {
        request = input instanceof Request ? input : null;
        url = request ? request.url : String(input);
        method = (init && init.method) || (request && request.method) || method;
        requestHeaders = Object.assign({}, toHeaderObject(request && request.headers), toHeaderObject(init && init.headers));
        requestBodyPreview = previewBody(init && Object.prototype.hasOwnProperty.call(init, 'body') ? init.body : request && request.body);
      } catch (_) {
        url = String(input);
      }

      var startedAt = now();
      var entry = push({
        type: 'fetch',
        phase: 'request',
        method: String(method || 'GET').toUpperCase(),
        url: url,
        requestHeaders: requestHeaders,
        requestBodyPreview: requestBodyPreview,
        startedAt: startedAt
      });

      return originalFetch.apply(this, arguments).then(function (response) {
        entry.phase = 'response';
        entry.status = response.status;
        entry.statusText = response.statusText;
        entry.ok = response.ok;
        entry.responseURL = response.url;
        entry.responseHeaders = toHeaderObject(response.headers);
        entry.endedAt = now();
        entry.durationMs = Math.round((entry.endedAt - startedAt) * 1000) / 1000;
        return response;
      }, function (error) {
        entry.phase = 'error';
        entry.error = error && (error.stack || error.message || String(error));
        entry.endedAt = now();
        entry.durationMs = Math.round((entry.endedAt - startedAt) * 1000) / 1000;
        throw error;
      });
    };
  }

  if (typeof OriginalXMLHttpRequest === 'function') {
    global.XMLHttpRequest = function AgentSafariXMLHttpRequest() {
      var xhr = new OriginalXMLHttpRequest();
      var entry = null;
      var requestHeaders = {};
      var startedAt = 0;
      var originalOpen = xhr.open;
      var originalSend = xhr.send;
      var originalSetRequestHeader = xhr.setRequestHeader;

      xhr.open = function (method, url) {
        entry = {
          type: 'xhr',
          phase: 'opened',
          method: String(method || 'GET').toUpperCase(),
          url: String(url || ''),
          requestHeaders: requestHeaders
        };
        return originalOpen.apply(xhr, arguments);
      };

      xhr.setRequestHeader = function (name, value) {
        requestHeaders[String(name).toLowerCase()] = String(value);
        return originalSetRequestHeader.apply(xhr, arguments);
      };

      xhr.send = function (body) {
        startedAt = now();
        if (!entry) entry = { type: 'xhr', method: 'GET', url: '', requestHeaders: requestHeaders };
        entry.phase = 'request';
        entry.requestBodyPreview = previewBody(body);
        entry.startedAt = startedAt;
        push(entry);
        return originalSend.apply(xhr, arguments);
      };

      xhr.addEventListener('loadend', function () {
        if (!entry) return;
        entry.phase = xhr.status === 0 ? 'error-or-cancel' : 'response';
        entry.status = xhr.status;
        entry.statusText = xhr.statusText;
        entry.responseURL = xhr.responseURL;
        entry.endedAt = now();
        entry.durationMs = Math.round((entry.endedAt - startedAt) * 1000) / 1000;
        try {
          var raw = xhr.getAllResponseHeaders();
          var headers = {};
          raw.trim().split(/[\r\n]+/).forEach(function (line) {
            var idx = line.indexOf(':');
            if (idx > 0) headers[line.slice(0, idx).trim().toLowerCase()] = line.slice(idx + 1).trim();
          });
          entry.responseHeaders = headers;
        } catch (_) {}
      });

      return xhr;
    };
    global.XMLHttpRequest.prototype = OriginalXMLHttpRequest.prototype;
  }
})(typeof window !== 'undefined' ? window : this);
