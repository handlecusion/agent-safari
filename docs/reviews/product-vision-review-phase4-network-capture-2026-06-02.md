# Product-Vision Review — Phase 4 Network Capture Hardening Slice

- Date: 2026-06-02
- Reviewer persona: product-vision guardian (`docs/PRODUCT_VISION.md`, `docs/PRODUCT_SPEC.md`, `docs/DEVELOPMENT_PHASES.md`)
- Scope: uncommitted Phase 4 network-capture-hardening slice (working tree, not yet committed)
- Mandate: confirm the slice strengthens evidence / failure explanation without overclaiming CDP / HAR / proxy capability
- Evidence basis: full `git diff` + new contract test + GUI smoke report `.tmp/agent-safari-5-scenarios-20260602-225141/REPORT.md` (5/5 PASS)

## VERDICT: PASS (with required fixes before Phase 4 close)

The slice is squarely on-vision. It strengthens the **Evidence** pillar (redaction policy + capture bounds now exposed in result metadata, redaction proven end-to-end against injected secrets) and **tightens honesty** rather than loosening it (adds `no downloads`, `not full HAR completeness`, `no default proxy capture` to the limitations set). No CDP/HAR/proxy overclaim is introduced or widened. Core named acceptance criteria are met.

Two newly-added result-metadata fields are self-inconsistent with the artifact they describe (F1, F2). They do not constitute an overclaim, so they do not block the PASS — but an evidence substrate must not emit metadata that contradicts its own artifact, so they are **required fixes before the phase is declared closed**.

## What the slice does

1. **Body-preview redaction** — new `sensitiveBodyPattern` (`sensitive-field|passwd|secret|token|api[_-]?key|authorization|cookie`); `redactBodyPreview` replaces a matching `requestBodyPreview` with `[REDACTED]` (`BrowserControllerNetwork.swift:41,52,58`).
2. **Honest limitations expanded** — artifact `limitations` array gains `no downloads`, `not full HAR completeness`, `no default proxy capture` (`:149`).
3. **Capture bounds + policy in artifact** — `bodyPreviewBytes`, `maxEntries`, `redactionPolicy` added to `agentSafari` block (`:151-155`).
4. **Result map enriched** — CLI/MCP `network export` result now returns `captureType`, `limitations`, `bodyPreviewBytes`, `maxEntries`, `eventCount`, `resourceTimingCount`, `redactionPolicy` (`:177-190`).
5. **Contracts** — MCP `network_export` result contract expanded (`mcp/agent_safari_mcp.py:52`); `test_mcp_contract.py` updated; new `Tests/test_network_capture_contract.py` (4 tests: honest+bounded metadata, redaction terms, MCP result fields, doc scope phrases). Both gates registered in `CLAUDE.md`.
6. **Smoke proves redaction at runtime** — fixture now injects `Auth header: Token should-redact`, `X-Redact-Token: should-redact-token`, and `sensitive-field: should-redact-sensitive-field`; smoke asserts `should-redact` absent from the export, required limitations present, and `captureType`/`bodyPreviewBytes` echoed (`scripts/smoke_real_world.py:479-480,577-587`).
7. **Docs** — Phase 4 → **Active** with refined work items/acceptance criteria; `PRODUCT_SPEC.md` reworded to "JavaScript fetch/XHR instrumentation … not full HAR capture".

## Honesty / scope — clean (the core mandate)

- **No overclaim.** `schema: "har-like"`, `captureType: "fetch-xhr-js-instrumentation"`, `redacted: true`, and the explicit limitations array all hold the line against CDP/HAR/proxy parity. The slice *adds* disclaimers; it removes none.
- **Vision §6 (honest scope) reinforced.** "no default proxy capture" / "not full HAR completeness" / "no downloads" now ride inside the artifact itself, so a downstream agent reading the export sees the boundary without consulting docs.
- **Redaction is real, not claimed.** The smoke run (`225141`, scenario 3 PASS) executes the leak check against three injected secrets — this is behavioral evidence, not a static assertion. Header allowlist (`authorization/cookie/set-cookie/x-api-<redacted>/x-redact-token/proxy-authorization`) covers the injected headers; body pattern covers the injected `sensitive-field`. Strong.
- **PRODUCT_SPEC / PHASES align with code.** No drift between documented capability and emitted metadata.

## Findings

### Required before Phase 4 close (evidence integrity, not overclaim)

- **F1 — `eventCount` in the result map misreports.** Result `eventCount` is set to `count` (`:187`), and `count` is computed as total HAR `entries` = fetch/xhr events **+** resource-timing entries (`:167-176`). The artifact uses the same name to mean fetch/xhr only: `eventCount: events.length` (`:153`). In the `225141` run (events=2, resourceTimings=2) the result would report `eventCount=4` while the artifact reports `eventCount=2`. Same field name, same export, two values — and the result value overstates how many network events were actually captured. Fix: emit the fetch/xhr-only count (and/or a distinct `entryCount`) so the result matches the artifact and the field name.
- **F2 — `resourceTimingCount` is a placeholder string.** Result returns the literal `"see-artifact"` (`:188`) instead of a number, while `eventCount` beside it is numeric. The MCP contract advertises `resourceTimingCount` as a result field, so a consumer expects a count. Fix: emit the real `resourceTimings.length` in the result map, or rename the field to signal it is a pointer.

### Non-blocking (should-fix / note)

- **F3 — "Body preview limits are tested" is not behaviorally verified.** The smoke passes `--body-preview-bytes 80` but only asserts the bound is *echoed* (`bodyPreviewBytes == '80'`); no test asserts an over-length body is actually truncated to N. The one body in the fixture is fully `[REDACTED]` before length matters, so trimming is exercised by neither the smoke nor the contract test (which only string-matches the trim source). Add a case with a long, non-sensitive body and assert preview length ≤ N to honor the acceptance criterion behaviorally.
- **F4 — limitations list differs between representations.** Artifact array has 8 items (`:149`); result-map semicolon string has 7 (`:184`) — it drops "no request/response headers for parser-driven resources". Minor, but the two honest lists should match.
- **F5 — `redactBodyPreview` nukes the whole preview on any match (note, not a defect).** A body that merely mentions `token`/`cookie` in a field name loses the entire preview. This is correctly conservative per Vision ("redaction conservative") but is lossy for evidence; a future key-level redaction would preserve more signal. No action required this phase.
- **F6 — carry-over: Phase 5 status still contradicts shipped behavior.** `DEVELOPMENT_PHASES.md:192` still marks Phase 5 **Gated** / "placeholder tab/session/profile commands" while smoke scenario 4 (`225141`) exercises a real `WKWebView` tab model (`tab-new`/`tab-switch`/session count). This was R2 follow-up #4 and remains open. Not introduced or worsened by this slice (this commit touches Phase 4, not Phase 5), so it stays non-blocking — fold the reconciliation into whichever commit next touches Phase 5.

## Evidence

- **Static review:** full `git diff` inspected; new metadata fields, redaction functions, and limitations present in `BrowserControllerNetwork.swift`; MCP contract + both contract tests updated; gates registered in `CLAUDE.md`.
- **GUI smoke `225141/REPORT.md`:** 5/5 PASS. Scenario 3 (fetch/XHR + resource timing) PASS with `eventCount: 2`, `resourceTimingCount: 2`, export written to `data/03_network.har.json`. Because the modified `smoke_real_world.py` carries the leak/limitation/metadata assertions, the PASS is runtime proof the redaction and honest-metadata path works end-to-end against injected secrets.
- **Caveat:** non-GUI gates (`test_network_capture_contract.py`, `test_mcp_contract.py`, `py_compile`) were **not** re-executed this session — Bash approval was declined, same posture as the Phase 3 R2 review. Basis is static review + the provided GUI smoke artifact. Run the registered gates at commit time:
  ```sh
  python3 Tests/test_network_capture_contract.py
  python3 Tests/test_mcp_contract.py
  python3 scripts/smoke_real_world.py
  ```

## Blockers

None. (F1/F2 are required fixes for phase *close*, not blockers for committing this slice — they are evidence-consistency defects, not overclaims.)

## Next track recommendation

1. **Close the loop on F1/F2** in this same slice or the immediate follow-up: make `eventCount`/`resourceTimingCount` in the result map agree with the artifact. This is the cheapest possible fix and directly serves "evidence over claims."
2. **Add the behavioral body-limit test (F3)** so the "Body preview limits are tested" acceptance criterion is true behaviorally, then Phase 4 can honestly close.
3. **Then stop broadening network capture.** Vision §6 + Hard Scope: proxy/HAR/WebSocket/downloads remain a separate opt-in research spike — do not pull them into Phase 4. Hold the discipline: contract test + GUI smoke artifact + honest status tag.
4. **When Phase 5 is next opened,** reconcile the Gated/placeholder wording (F6) against the real WKWebView tab model already shown in smoke.
