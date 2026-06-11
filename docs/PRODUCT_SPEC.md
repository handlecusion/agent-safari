# Agent Safari Product Specification

> This spec turns `docs/PRODUCT_VISION.md` into an executable product contract. Update it whenever scope, phase acceptance, or public positioning changes.

## 1. Product Identity

Agent Safari is a local-first macOS WebKit automation daemon for AI agents. It exposes a real WKWebView window through a CLI and a thin MCP wrapper so agents can perform an observe → act → wait → verify loop with evidence.

Agent Safari is:

- a native WebKit browser-control substrate for AI agents;
- a CLI-first and MCP-compatible local daemon;
- an evidence-producing QA/release helper;
- a tool for reliable rendered-page inspection, element refs, input, screenshots, waits, and network metadata.

Agent Safari is not:

- a general consumer browser;
- a hosted multi-user browser service;
- a Playwright replacement for deterministic test suites;
- a full Chrome DevTools Protocol or HAR-grade capture replacement;
- a passkey/WebAuthn automation project.

## 2. Target Users

### Primary: Local AI-agent operators

People running Hermes, Claude Code, Codex-style agents, or MCP clients who need a local browser that agents can see and operate.

Needs:

- inspect rendered pages;
- select and act on elements without hand-writing selectors;
- verify web UI behavior after code changes;
- capture evidence for debugging, reviews, releases, and reports;
- keep the browser local and human-observable.

### Secondary: Developers testing WebKit behavior

Developers who want agent-driven checks against WebKit/macOS instead of Chromium-only automation.

Needs:

- repeatable local smoke checks;
- visible WebKit behavior;
- explicit limitations and failure diagnostics.

## 3. Core Jobs To Be Done

1. **Observe a real page**
   - Navigate to a URL.
   - Read page text/HTML/title/URL.
   - Get an actionable DOM snapshot with stable `@e` refs.
   - Capture screenshots for evidence.

2. **Act through an agent-safe interface**
   - Click a ref or selector.
   - Fill or type into editable targets.
   - Send common key paths and shortcuts.
   - Prefer latest snapshot refs over invented selectors.

3. **Wait for state**
   - Wait for page readiness, text, selector presence, or network idle.
   - Return bounded timeout errors.
   - Avoid unbounded agent loops.

4. **Verify and report**
   - Re-observe after action.
   - Capture screenshot/network/text evidence.
   - Produce structured results and smoke artifacts.

5. **Explain failure**
   - Detect disabled, hidden, stale, off-viewport, occluded, and non-hittable targets.
   - Report fallback use and native-click verification status.
   - Prefer structured errors over silent no-ops.

## 4. Current Capabilities Contract

The current product contract after `v0.0.6` includes:

- native Swift/AppKit/WKWebView daemon;
- Unix-domain-socket control path;
- CLI with one JSON response line per command;
- thin Python MCP wrapper delegating to the CLI;
- navigation, status, observe, text, content/HTML, URL/title, evaluate;
- viewport, screenshot, full-page screenshot, screenshot-element;
- screenshot result metadata for output path, viewport/page size, scale, tile count/preflight scroll count, strategy, and warnings;
- full-page screenshot preflight scrolling for tall pages so lazy/intersection-observed content has a chance to render before capture while original scroll is restored;
- observe metadata for load state, pending network count, selected text, viewport/page size, and active element selector;
- snapshot refs with schema/actionability metadata;
- click, fill, type, key;
- stable actionability/native-input JSON-RPC error codes for current click/fill failure classes, raised from structured actionability results before falling back to legacy message classification;
- waits for URL, title, visible selector, idle, selector, text, loaded state, downloads, and media playback states, with bounded structured timeout failures;
- JavaScript fetch/XHR instrumentation for network metadata capture, list, stop, and redacted export;
- network export may include PerformanceResourceTiming entries for parser-driven resources, but this is not full HAR capture: no WebSocket frames, no service worker internals, no capture of download traffic (file downloads themselves are a separate first-class command surface), and no default proxy capture;
- network export must keep body preview limits explicit and redaction conservative for sensitive headers and body previews;
- console/page-error capture (`console start|list|stop`) as JavaScript instrumentation with per-tab isolation, mirroring the network capture honesty limits;
- JS dialog suppression with per-tab evidence (`suppressedDialogs`, `suppressedDialogCount`) and a per-command `--confirm accept|dismiss` policy;
- file upload (`upload`) with two-tier delivery: native open-panel on the visible tab when Accessibility permits, deterministic DataTransfer fallback otherwise, with explicit `upload_*` error codes;
- downloads via WKDownloadDelegate with a no-hang contract (`downloadStarted`/`downloadId` evidence on the triggering command), a `downloads` list, and `wait-for-download`;
- cookie export/import through WKHTTPCookieStore (0600 export files, session-wide store shared by all tabs, cross-daemon transfer);
- media observation and control (`media`, `wait-for-media`, `media-control`) limited to in-page element state — no stream reassembly, no DRM handling, no media segment downloading;
- session snapshot artifacts (`session-snapshot`) recording session/tab/capture state for parallel-run failure reports;
- parallel multi-tab targeting: every page command accepts `--tab <id>`, commands on different tabs run concurrently, every result reports the `tabId` it acted on, and per-tab state (navigation, captures, evidence) is isolated by tab;
- modeled session/tab/profile command surface inside one daemon and one native WebKit window: each modeled tab has a `WKWebView`, one tab is active at a time, and all tabs share the daemon's selected persistence mode;
- public release gates and smoke artifacts.

## 5. Quality Bar

A feature is complete only when it has:

1. CLI behavior and JSON result semantics documented.
2. MCP parity, or an explicit note that the command is intentionally CLI-only.
3. Contract tests for parser/schema/actionability behavior when applicable.
4. Smoke coverage if behavior touches real WebKit, input, screenshots, waits, or network capture.
5. Failure semantics for common invalid states.
6. Docs updated in the relevant file under `docs/`.
7. A vision-review pass against `docs/PRODUCT_VISION.md`.

## 6. Agentic Ref Contract

Snapshot refs are a product primitive, not a debug detail.

A snapshot ref must aim to provide:

- stable ordering for repeated observations of the same DOM state;
- enough metadata for an agent to choose targets;
- role/name/text/selector/bounds/actionability clues;
- explicit errors when a ref is stale or cannot be acted on;
- no silent fallback that hides a target/action mismatch.

Future ref improvements should prioritize reliability and explanation before adding more metadata.

## 7. Native Input Contract

Input reliability is a near-term priority because it directly affects the product promise.

The input surface must support:

- `input`, `textarea`, and `contenteditable` fields;
- normal text entry;
- `Enter`, `Backspace`, and common select-all shortcuts;
- focus transitions;
- structured reporting of native, synthetic, and fallback behavior.

Native click and native typing may remain environment-sensitive, but default behavior must say when fallback was used. Strict native-only gates should be opt-in and documented.

Native click target preparation must also report whether the target was scrolled into view, which viewport center/bounds were used, and whether center-hit testing found an occluder before posting native events.

Current stable actionability/native-input error codes:

- `actionability_stale_ref`
- `actionability_refs_unavailable`
- `actionability_missing_selector`
- `actionability_disabled`
- `actionability_hidden`
- `actionability_off_viewport`
- `actionability_occluded`
- `native_click_unverified`
- `native_input_failed`

## 8. Evidence Contract

Agent Safari should make actions auditable.

Evidence surfaces include:

- JSON CLI/MCP responses;
- smoke `REPORT.md` files;
- screenshots and element screenshots;
- screenshot metadata in smoke evidence, including viewport/page dimensions, scale, tile count/preflight scroll count, strategy, and warnings;
- observe metadata in smoke evidence, including load state, pending network count, selected text, viewport/page dimensions, and active element selector;
- bounded wait-predicate success/failure evidence for URL/title/visible waits;
- typed actionability/native-input `error.code` values and `nativeErrorCode` fallback metadata;
- focused strict-native probe artifacts that record `native-verified` or `environment-gated` without changing the strict hard gate;
- network export JSON with JavaScript fetch/XHR instrumentation metadata, PerformanceResourceTiming limitations, body preview bounds, and redaction policy;
- daemon logs;
- CI/release workflow output;
- artifact checksum verification.

Docs and release notes should point to real evidence, not inferred success.

## 9. Scope Boundaries

Do not add these without a separate decision note and phase update:

- passkey/WebAuthn automation;
- default proxy/HAR capture;
- browser extension dependency;
- cloud-hosted multi-user architecture;
- true profile/session isolation beyond the current one-daemon modeled tab contract;
- claims of CDP parity.

## 10. Open Product Questions

- Which additional native-click/actionability codes should be added beyond the current stable taxonomy?
- Which occlusion checks are stable enough across macOS/WebKit environments?
- Which future cookie/profile APIs should graduate beyond the current one-daemon modeled tab contract?
- Which GUI checks can run reliably in GitHub Actions, if any?
