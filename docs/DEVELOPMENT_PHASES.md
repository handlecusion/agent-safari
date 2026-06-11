# Agent Safari Phased Development Plan

> Build Agent Safari through evidence-backed phases. Each phase must preserve the product vision in `docs/PRODUCT_VISION.md`, the product contract in `docs/PRODUCT_SPEC.md`, and the observe → act → wait → verify loop in `docs/AGENT_LOOP.md`.

## Operating Model

Every phase follows the same loop:

1. **Plan** — write or update the phase section and acceptance criteria before coding.
2. **Implement** — keep changes small and commit-worthy.
3. **Verify** — run the phase gates and capture real output/artifacts.
4. **Vision review** — ask a Claude Code session using `docs/PRODUCT_VISION.md` as its reviewer persona to check alignment and overreach.
5. **Document** — update specs, usage docs, roadmap, release checklist, and wiki evidence.
6. **Commit** — commit code and docs together when they prove the same milestone.

## Phase Status Legend

- **Done** — implemented, tested, documented, and released or merged.
- **Active** — current workstream.
- **Planned** — accepted direction but not started.
- **Gated** — do not implement until a preceding phase proves the needed foundation.
- **Research** — exploratory only; no product claims until verified.

## Vision Priority Crosswalk

- `docs/PRODUCT_VISION.md` Priority 1, strict native click/actionability hardening → Phase 2.
- `docs/PRODUCT_VISION.md` Priority 2, capture and inspection metadata → Phase 3.
- `docs/PRODUCT_VISION.md` Priority 3, session/browser model after modeled WebView stability → Phase 5.
- Network export beyond the current fetch/XHR instrumentation → Phase 4.
- Packaging, installation, public demo, and distribution polish → Phase 6.

## Phase 0 — Public Release Hygiene

Status: Done through `v0.0.6`.

Goal: Make the repository safe and useful as a public open-source project.

Completed capabilities:

- MIT license;
- clean public repository baseline;
- public GitHub description, topics, and release artifacts;
- CI on macOS;
- public-release audit;
- release checklist;
- Homebrew/GitHub release packaging path;
- npm wrapper prepared but unpublished.

Acceptance criteria:

- `scripts/public_release_audit.py` passes.
- Release assets can be downloaded and checksum-verified.
- Docs do not leak local-only paths, secrets, or unsupported claims.

## Phase 1 — Deterministic Smoke And Agent Loop Baseline

Status: Done through `v0.0.6`.

Goal: Prove that a real WebKit daemon can support repeatable observe → act → wait → verify workflows.

Completed capabilities:

- CLI smoke;
- MCP wrapper smoke;
- five-scenario real-world smoke;
- bounded smoke artifacts;
- screenshot evidence;
- network metadata scenario;
- native input smoke scenario;
- release gate documentation.

Acceptance criteria:

- `bash scripts/smoke_cli.sh` exits 0.
- `python3 scripts/smoke_mcp_wrapper.py` exits 0 where applicable.
- `python3 scripts/smoke_real_world.py` reports `5/5 PASS` from a logged-in GUI session.
- Smoke report paths are recorded in release/wiki notes.

## Phase 2 — Native Input And Agentic Refs Trust

Status: Done for the current Phase 2 reliability contract, with strict native delivery explicitly environment-gated. Reopen this phase only for regressions or when the local GUI environment can prove native-only delivery.

Goal: Make element selection and browser actions reliable enough that agents can trust snapshot refs and understand failures.

Completed checkpoints:

- snapshot schema v2 and stable DOM-order indexing;
- agentic refs contract tests;
- actionability validation for hidden/disabled/off-viewport targets;
- stable JSON-RPC actionability/native-input error codes for current click/fill failure classes;
- input/textarea/contenteditable key-path coverage;
- `Enter`, `Backspace`, and select-all shortcut coverage;
- real-world smoke scenario 5.

Current checkpoint work:

1. Hardened `click --native` focus/fallback reporting.
2. Improved coordinate conversion and viewport scroll metadata before click.
3. Added center-hit occlusion diagnostics in the click target preparation path.
4. Refined hittable errors with explicit occlusion and actionability messages.
5. Kept CLI/MCP-compatible structured result fields for new input/actionability metadata.

Closure evidence:

1. Strict native local run with `AGENT_SAFARI_STRICT_NATIVE=1` currently fails in this environment with `Native Quartz click posted but no DOM click event was observed`; this is accepted as an explicit environment gate, not a product success claim.
2. Runtime smoke coverage triggers center-hit occlusion diagnostics before native/DOM fallback actions.
3. Runtime smoke records non-zero scroll metadata on a deliberately offscreen editable target (`#typed` reports `scrollDeltaY: 729`, `scrolledIntoView: true` in `.tmp/agent-safari-5-scenarios-20260602-202144/data/scenario-results.json`).
4. Product-vision reviewer validated that Phase 2 should remain honest about strict native environment sensitivity.

Current strict-native-click slice acceptance:

- `elementHitTarget` records scroll position before/after `scrollIntoView` so agents can tell whether a target required scrolling.
- The hit target is validated with `document.elementFromPoint` after scrolling; truly occluded centers fail with an explicit `Element center is occluded` error before native or DOM fallback actions.
- Native click results include viewport bounds/center, scroll delta, coordinate strategy, native verification, fallback use, and native error where applicable.
- Native fallback results include `nativeErrorCode`, and click/fill actionability failures expose typed JSON-RPC `error.code` values from structured WebKit evaluation results while preserving human-readable messages.
- `--strict-native-probe` records focused strict-native evidence as either `native-verified` or `environment-gated` without converting the strict hard gate into a success claim.
- Contract tests lock the above strings/fields so future refactors do not silently drop diagnostics.

Verification on 2026-06-02 for the fallback-documented checkpoint:

- `python3 Tests/test_agentic_refs_contract.py`
- `python3 Tests/test_smoke_real_world.py`
- `swift test`
- `python3 scripts/smoke_real_world.py --skip-build` → report at `.tmp/agent-safari-5-scenarios-20260602-202144/REPORT.md`; native click used DOM fallback in this local session and remains environment-sensitive; occlusion diagnostic smoke path fired before fallback scenario.
- `AGENT_SAFARI_STRICT_NATIVE=1 python3 scripts/smoke_real_world.py --skip-build` failed at strict native click with `Native Quartz click posted but no DOM click event was observed`, confirming strict native is environment-gated here rather than complete.

Post-Phase 5 actionability taxonomy verification on 2026-06-04:

- `swift test`
- `python3 Tests/test_agentic_refs_contract.py`
- `python3 Tests/test_mcp_contract.py`
- `python3 Tests/test_smoke_real_world.py`
- `bash scripts/smoke_cli.sh`
- `python3 scripts/smoke_real_world.py --skip-build --out-dir .tmp/agent-safari-5-scenarios-r2-fixed` → report at `.tmp/agent-safari-5-scenarios-r2-fixed/REPORT.md`; scenario 5 records `nativeErrorCode: native_click_unverified` for fallback and verifies runtime actionability codes for refs unavailable, missing selector, disabled, hidden, off-viewport, stale ref, and occluded center-hit failures.
- `python3 scripts/smoke_real_world.py --skip-build --strict-native-probe --out-dir .tmp/agent-safari-strict-native-probe-r2-fixed` → report at `.tmp/agent-safari-strict-native-probe-r2-fixed/REPORT.md`; current local GUI result is `environment-gated` with `error.code: native_click_unverified`.
- `AGENT_SAFARI_STRICT_NATIVE=1 python3 scripts/smoke_real_world.py --skip-build --out-dir .tmp/agent-safari-strict-hard-gate-r2-fixed` failed as expected in this environment with JSON-RPC `error.code: native_click_unverified`, preserving the strict-native environment gate.

Acceptance criteria:

- Contract tests cover new ref/actionability semantics.
- Real-world smoke includes at least one target that requires scroll/focus handling.
- Strict native-only mode either passes in a suitable local environment or reports a documented environment-sensitive failure.
- Default fallback behavior always records method, native verification, fallback use, and native error when applicable.

Recommended gates:

```sh
swift test
python3 Tests/test_agentic_refs_contract.py
python3 Tests/test_input_keypath_contract.py
python3 Tests/test_browser_chrome_contract.py
python3 Tests/test_capture_inspection_contract.py
bash scripts/smoke_cli.sh
python3 scripts/smoke_real_world.py
```

## Phase 3 — Capture And Inspection Metadata

Status: Product-vision reviewed and Done for the current capture/inspection reliability contract. Further full-page rendering fidelity remains an enhancement, not a blocker for Phase 3 closure.

Goal: Give agents richer page state and screenshot context without overclaiming browser-level control.

Completed in current checkpoint:

1. Screenshot commands now report output path, viewport size, page size, scale, tile count, preflight scroll count for full-page capture, strategy, and warnings in CLI/MCP result metadata.
2. Full-page screenshot now preflight-scrolls tall pages to trigger lazy/intersection-observed content and restores the original scroll position before returning evidence.
3. `observe` now reports load state, pending network count, selected text, viewport/page size, and active element selector alongside URL/title and existing active element fields.
4. Wait predicates now include URL substring, title substring, and visible-selector waits in addition to selector/text/idle waits, with bounded structured timeout failures.
5. Contract coverage added in `Tests/test_capture_inspection_contract.py`, Swift command metadata tests, and MCP contract tests for screenshot/observe/wait result fields.
6. Real-world smoke now validates screenshot command metadata, lazy-load preflight scroll evidence, observe metadata, URL/title/visible waits, and bounded visible-wait failure evidence in scenario artifacts.

Remaining Phase 3 work:

1. Optional future enhancement: refine full-page stitching around fixed headers and unusual high-DPI edge cases if smoke or users show evidence gaps.
2. Keep new wait predicates narrow and documented; do not expand into unsupported browser automation claims without a decision note.

Acceptance criteria:

- Screenshot commands return structured metadata in CLI and MCP responses. Done for the current metadata fields, including full-page `preflightScrollCount`.
- Metadata fields are contract-tested. Done for screenshot/observe/wait/MCP fields.
- Full-page smoke proves the captured image is taller than the viewport image and that preflight scroll triggers lazy content while restoring scroll. Done in `.tmp/agent-safari-5-scenarios-20260602-224013/REPORT.md`.
- Waits remain timeout-bounded and return structured errors. Done for URL/title/visible plus existing selector/text/idle waits.

## Phase 4 — Network Capture Hardening

Status: Product-vision reviewed and Done for the current network capture hardening contract.

Goal: Improve network evidence while keeping scope honest.

Completed:

1. JavaScript fetch/XHR instrumentation export now reports capture type, limitation list, body preview bound, max-entry bound, entry count, fetch/XHR event count, PerformanceResourceTiming count, and redaction policy.
2. Network export documents unsupported capture classes: parser resources via PerformanceResourceTiming only, no request/response headers for parser-driven resources, no WebSocket frames, no service worker internals, no downloads, not full HAR completeness, and no default proxy capture.
3. Redaction remains conservative for sensitive headers and body previews.
4. Real-world smoke verifies sensitive fixture values do not leak and a 200-byte non-sensitive POST body is trimmed to the requested 80-byte preview.
5. Claude Code product-vision reviewer R3 passed the slice and confirmed Phase 4 may close.

Acceptance criteria:

- Export schema is documented and contract-tested. Done.
- Body preview limits are tested. Done in `.tmp/agent-safari-5-scenarios-20260602-230730/REPORT.md`.
- Docs clearly say this is JavaScript fetch/XHR instrumentation plus limited PerformanceResourceTiming, not full browser capture. Done.
- MCP/CLI result metadata exposes capture type, limitations, body preview bounds, and redaction policy. Done.

## Phase 5 — Session, Tab, And Profile Model

Status: Product-vision reviewed and Done for the current modeled session/tab/profile contract.

Goal: Make the shipped daemon session, modeled tab, and profile-persistence semantics explicit without overclaiming true browser/profile isolation.

Completed in current checkpoint:

1. `docs/PROFILE_PERSISTENCE.md` is the Phase 5 design note for the current model.
2. A session means one daemon process on one Unix socket, with one `sessionId`, one native WebKit window, one active tab id, and one selected persistence mode.
3. A tab means one in-process modeled target backed by a `WKWebView`; one tab is active and attached to the native window at a time.
4. A profile means daemon startup metadata plus the selected `WKWebsiteDataStore`: persistent mode uses WebKit's default store, while `--ephemeral` uses a non-persistent store. Named per-profile stores are not implemented.
5. MCP multi-session behavior is socket-scoped: clients target one daemon through `AGENT_SAFARI_SOCKET`; multiple sessions require multiple daemons/sockets.
6. Artifact isolation is caller-owned path isolation. Smoke runs create per-run artifact directories; the daemon does not maintain a separate artifact namespace per tab/profile.
7. CLI/MCP contracts expose the current session/tab fields and are pinned by contract tests.
8. Real-world smoke exercises modeled tab creation, switching, tab close/last-tab refusal, session metadata, active-tab flags, and ephemeral data-store reporting (`.tmp/agent-safari-5-scenarios-20260604-154342/REPORT.md`).
9. Product-vision reviewer passed the close in `docs/reviews/product-vision-review-phase5-session-tab-profile-2026-06-04.md`.

Future work, not part of this closed contract:

1. Cookie export/import tools using `WKHTTPCookieStore`.
2. Named profile registry under `~/.agent-safari/profiles/<name>/metadata.json`.
3. Explicit clear-profile command for destructive test isolation.
4. Session snapshot artifacts that record active tab id, URLs, viewport, capture settings, and artifact paths. **Implemented (2026-06-11)**: `session-snapshot <path>` command writes a schema-version-1 JSON artifact with sessionId, profile, persistent, dataStore, activeTabId, viewport, and per-tab state (url, title, loading, networkCapturing, consoleCapturing, pendingSuppressedDialogCount). Contract-tested in `Tests/test_session_snapshot_contract.py`; smoke-verified in `scripts/smoke_cli.sh`.
5. True profile/session isolation beyond the current one-daemon model.

Acceptance criteria:

- A written design note exists. Done in `docs/PROFILE_PERSISTENCE.md`.
- Existing daemon/window commands remain deterministic. Done for current command surface.
- New IDs and lifecycle commands are contract-tested. Done through Swift parser tests, MCP contract tests, and `Tests/test_session_profile_contract.py`.
- State cleanup and isolation boundaries are documented and smoke-tested. Done for current daemon/socket/ephemeral/artifact contract in `.tmp/agent-safari-5-scenarios-20260604-154342/REPORT.md`.

## Phase 5.5 — Parallel Multi-Tab Targeting (2026-06-11)

Status: Implemented, gate-verified, and product-vision reviewed (2026-06-11); live evidence below.

Verified evidence (2026-06-11):

- CLI smoke proves a `title --tab tab-2` returns in 81ms while a 6s `wait-for-selector`
  runs on tab-1, and parallel navigates land on their own tabs (`scripts/smoke_cli.sh`,
  "verifying parallel multi-tab targeting" section).
- Live daemon run verified: per-tab routing with `tabId` evidence, `unknown_tab`,
  `navigation_in_progress`, `tab_not_active_for_native_input` error codes, per-tab
  network capture flags, popup redirect on a background tab staying on that tab, and a
  non-blank 2560x1440 background-tab screenshot (background rendering is supported).
- Contracts pinned in `Tests/test_multitab_parallel_contract.py` and
  `Tests/test_mcp_contract.py`; full gate suite plus `scripts/smoke_real_world.py` pass.

Decision note (2026-06-11): The user explicitly reopened the multi-tab scope boundary for
parallel work. Scope is limited to per-command tab targeting and concurrent command
handling inside the existing single-window, shared-cookie session model. Per-tab
profile/cookie isolation, multiple native windows, and hosted multi-session remain out of
scope; isolation still means one daemon per socket.

Goal: Let multiple agent clients drive different tabs of one daemon concurrently, with
per-tab evidence and explicit failure codes, without breaking the Phase 5 modeled
session/tab contract for callers that never pass a tab id.

Contract:

1. Every RPC method accepts an optional `tab` param (CLI `--tab <id>`, MCP `tab` input).
   Omitted means the active tab — existing callers see unchanged behavior.
2. An unknown tab id fails with the stable `unknown_tab` error code before any action runs.
3. Long waits on one tab must not block commands on other tabs.
4. Concurrent navigations on different tabs are isolated; a second navigate on a tab whose
   navigation is still in flight fails with `navigation_in_progress` instead of silently
   replacing the pending wait. Closing a tab fails its in-flight navigation explicitly.
5. Network capture state, snapshot refs, and popup-redirect evidence are per-tab.
6. Every command result reports the `tabId` it acted on.
7. Native (Quartz) input targets the visible tab only; native input addressed to a
   background tab fails with an explicit error code rather than clicking the wrong page.
8. Background-tab rendering limits (screenshot/viewport) are measured, then either
   supported or rejected with an explicit error code — no silent wrong-tab artifacts.

Acceptance criteria:

- Contract test pins tab-param routing, per-tab state isolation, and error codes.
- CLI smoke proves a long wait on tab A does not delay a click on tab B, and parallel
  navigations land on their own tabs.
- Docs (`CLI_USAGE.md`, `MCP_WRAPPER.md`, this note) describe the shared-cookie,
  single-window limits explicitly.
- Product-vision review passes for the slice.

## Phase 5.6 — Agent Reliability And Evidence Wave (2026-06-11)

Status: Closed. Implemented and gate-verified across nine parallel slices developed the
same day; slices 1–2 merged at `7bcd205`/`d640f3c` and slices 3–9 in the
`fd14c58..e66a82f` merge train. Product-vision review recorded in
`docs/reviews/product-vision-review-phase5.6-agent-reliability-2026-06-11.md`.
Consolidated closing evidence: full gate suite (swift test 60/60, release build, all
contract tests, `scripts/smoke_cli.sh`, `scripts/smoke_real_world.py`) passed with the
GUI report at `.tmp/agent-safari-5-scenarios-20260611-202525/REPORT.md`.

Goal: Close the largest remaining "silent no-op" and "missing evidence" gaps an agent hits
in real pages, keeping every new capability inside the observe → act → wait → verify loop.

Shipped slices (each with its own contract test, smoke coverage, and live verification):

1. Same-document navigation fix (merged `d640f3c`) — fragment-only `navigate` no longer
   hangs forever; returns immediately with `sameDocument: true`
   (`Tests/test_same_document_nav_contract.py`).
2. Stable error codes (merged `7bcd205`) — `wait_timeout`, `invalid_url`, and nine more
   replace the generic `"error"`; the errorCode switch is exhaustive
   (`Tests/test_error_code_contract.py`).
3. JS dialog evidence — suppressed alert/confirm/prompt reported per tab in click results
   (`suppressedDialogs`) and `observe`; per-command `--confirm accept|dismiss`
   (`Tests/test_dialog_evidence_contract.py`).
4. Console/page-error capture — `console start|list|stop` mirroring the network trio,
   per-tab isolation verified live (`Tests/test_console_capture_contract.py`).
5. File upload — `upload` command with two-tier delivery: native open-panel on the visible
   tab when Accessibility permits, deterministic DataTransfer fallback otherwise (8 MB/file
   cap, `upload_*` error codes). The original synthetic-click design never opened the panel
   — WebKit requires real user activation — and was caught by live verification
   (`Tests/test_upload_contract.py`).
6. Downloads — WKDownloadDelegate with the no-hang contract: a navigate that becomes a
   download resumes with `downloadStarted`/`downloadId` evidence; `downloads` +
   `wait-for-download`; files land under `~/.agent-safari/downloads/<id>/`
   (`Tests/test_download_contract.py`).
7. Session snapshot — `session-snapshot <path>` dumps session/tab/capture state for
   parallel-run failure reports (Phase 5 future item 4, `Tests/test_session_snapshot_contract.py`).
8. Cookie export/import — WKHTTPCookieStore transfer with 0600 exports and cross-daemon
   import verified live (Phase 5 future item 1, `Tests/test_cookie_transfer_contract.py`).
   The smoke for this section runs exclusively on throwaway `--ephemeral` daemons after a
   review catch: exporting from the shared persistent store dumps the user's real cookies.
9. Media observation and control — `media` inventory, `wait-for-media` predicates,
   `media-control play|pause|mute|unmute|seek` with `media_play_rejected` evidence;
   programmatic playback enabled by configuration. Scope ends at observation/control per
   the media hard boundary (`Tests/test_media_contract.py`).

## Phase 6 — Productization And Distribution

Status: Planned.

Goal: Make installation, MCP registration, releases, and demos reliable for external users.

Work items:

1. Keep Homebrew tap release flow verified.
2. Decide if/when npm package should be published.
3. Keep `agent-safari-mcp-setup` consent-first and client-aware.
4. Maintain public README demo clarity.
5. Add a minimal public demo that communicates the browser-control substrate without overclaiming CDP parity.

Acceptance criteria:

- Release checklist remains accurate.
- Install docs match actual artifacts.
- Public demo exercises observe → act → wait → verify.

## Phase Review Checklist

Before closing any phase:

- [ ] Does the work strengthen eyes, hands, evidence, or failure explanation?
- [ ] Are unsupported CDP/HAR/passkey/session claims avoided?
- [ ] Are CLI and MCP semantics aligned?
- [ ] Are contract tests updated?
- [ ] Is GUI smoke updated if the behavior touches WebKit runtime?
- [ ] Did a Claude Code product-vision reviewer inspect the change?
- [ ] Are docs and wiki evidence updated?
