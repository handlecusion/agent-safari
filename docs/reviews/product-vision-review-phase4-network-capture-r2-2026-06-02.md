# Product-Vision Review R2 — Phase 4 Network Capture Hardening Slice

- Date: 2026-06-02
- Reviewer persona: product-vision guardian (`docs/PRODUCT_VISION.md`, `docs/PRODUCT_SPEC.md`, `docs/DEVELOPMENT_PHASES.md`)
- Scope: re-review of the uncommitted Phase 4 network-capture-hardening slice after the F1/F2 fixes flagged in `product-vision-review-phase4-network-capture-2026-06-02.md` (R1)
- Mandate: confirm the required-before-close evidence-integrity fixes (F1, F2) landed without introducing CDP/HAR/proxy overclaim, and decide whether Phase 4 may close
- Evidence basis: direct read of `Sources/AgentSafari/BrowserControllerNetwork.swift`, `mcp/agent_safari_mcp.py`, `Tests/test_network_capture_contract.py`, `Tests/test_mcp_contract.py`, `scripts/smoke_real_world.py`; new GUI smoke report `.tmp/agent-safari-5-scenarios-20260602-225601/REPORT.md` (5/5 PASS)

## VERDICT: PASS — Phase 4 may close

R1's two required-before-close fixes (F1, F2) are landed and verified. The slice remains squarely on-vision: it strengthens the **Evidence** pillar and **tightens honesty** (no CDP/HAR/proxy overclaim added or widened). The metadata self-inconsistency that held the phase open in R1 is gone — the result map no longer contradicts the artifact it describes. **Phase 4 can be declared closed.**

Three non-blocking items remain (F3, F4 carried from R1; F5/F6 unchanged). None is an overclaim; none blocks close. Fold them into the next touching commit.

## R1 required fixes — both confirmed closed

### F1 (`eventCount` misreported total entries) — FIXED
- The result map now emits **two distinct fields**: `entryCount` = total HAR `entries` (`count`), and `eventCount` = fetch/xhr-only count parsed back from the artifact's `agentSafari.eventCount` (`BrowserControllerNetwork.swift:208-209`).
- The export-side parse reads `agentSafari.eventCount` / `agentSafari.resourceTimingCount` from the just-written artifact (`:174-184`), so the result and the artifact now carry the **same value under the same name**. `eventCount` no longer overstates captured network events.
- Coverage extended: `entryCount` is now a declared field in the MCP `network_export` result contract (`mcp/agent_safari_mcp.py:52`), in `Tests/test_mcp_contract.py:108`, and asserted in `Tests/test_network_capture_contract.py:50,84`.

### F2 (`resourceTimingCount` was the literal `"see-artifact"`) — FIXED
- The result map now emits the real number: `"resourceTimingCount": String(resourceTimingCount)` (`:210`), sourced from the artifact's `resourceTimings.length` (`:180-181`).
- Contract test pins the regression shut: `assert '"resourceTimingCount": "see-artifact"' not in source` and `assert '"resourceTimingCount": String(resourceTimingCount)' in source` (`Tests/test_network_capture_contract.py:49,52`).
- Smoke confirms the runtime value is a number: scenario 3 reports `resourceTimingCount: 2` (`225601/REPORT.md:71`).

## Honesty / scope — still clean (core mandate)

- **No overclaim introduced.** `schema: "har-like"`, `captureType: "fetch-xhr-js-instrumentation"`, `redacted: true`, and the 8-item artifact `limitations` array (`:149`) all hold the line against CDP/HAR/proxy parity. The fixes only made the *counts* honest; they added no capability claim.
- **Redaction still proven, not asserted.** Smoke `225601` scenario 3 PASS executes the leak check against injected `Auth header: Token should-redact`, `X-Redact-Token: should-redact-token`, and body `sensitive-field: should-redact-sensitive-field`, and asserts `should-redact` is absent from the export (`scripts/smoke_real_world.py:479-480,580-581`). Behavioral evidence, not a static claim.
- **Doc/code alignment holds.** `test_phase4_docs_state_current_scope_boundaries` pins the honest scope phrases across `PRODUCT_SPEC.md` + `DEVELOPMENT_PHASES.md` (`Tests/test_network_capture_contract.py:92-106`).

## Remaining non-blocking items

- **F3 — body-preview limit still not behaviorally verified (carried from R1).** Smoke passes `--body-preview-bytes 80` but only asserts the bound is *echoed* (`bodyPreviewBytes == '80'`, `smoke_real_world.py:586`). The one XHR body in the fixture contains `sensitive-field`, so it is fully `[REDACTED]` before length matters; the fetch has no body. The contract test only string-matches the trim guard source (`"bodyPreviewBytes !== null"`, `test_network_capture_contract.py:47`). No test proves an over-length, non-sensitive body is actually truncated to N. Add a long non-sensitive body case asserting preview length ≤ N to make "body preview limits are tested" true behaviorally.
- **F4 — limitations list still differs between representations (carried from R1).** Artifact array has 8 items (`BrowserControllerNetwork.swift:149`); the result-map semicolon string has 7 (`:205`) — it still drops `"no request/response headers for parser-driven resources"`. The contract test's `required_limitations` set (`test_network_capture_contract.py:35-43`) also omits that phrase, so the gap is unpinned. Minor; the two honest lists should match. Align the result string (and add the phrase to the contract set) in the next touching commit.
- **F5 — `redactBodyPreview` nukes the whole preview on any match (note, not a defect).** Unchanged. Correctly conservative per Vision; lossy for evidence. Future key-level redaction would preserve more signal. No action this phase.
- **F6 — Phase 5 Gated/placeholder wording still contradicts shipped tab behavior (carry-over).** Smoke `225601` scenario 4 PASS exercises a real `WKWebView` tab model (`tab-new`/`tab-switch`, `tabCount: 2`, nonPersistent session) — stronger than the "placeholder tab/session/profile commands" wording. Not introduced or worsened by this Phase-4 slice. Reconcile when a commit next touches Phase 5.

## Evidence

- **Static review (this session):** read current `BrowserControllerNetwork.swift:140-213` — confirmed distinct `entryCount`/`eventCount`/`resourceTimingCount` in the result map, artifact-sourced counts, no `"see-artifact"` literal. Confirmed MCP contract (`:52`) and both contract tests carry `entryCount` + the numeric-count assertions.
- **GUI smoke `225601/REPORT.md`:** 5/5 PASS. Scenario 3 PASS with `eventCount: 2`, `resourceTimingCount: 2`, export written to `data/03_network.har.json`. Because the modified `smoke_real_world.py` carries the leak/limitation/metadata assertions, this PASS is runtime proof the honest-metadata + redaction path works end-to-end against injected secrets.
- **Caveat:** non-GUI contract gates (`test_network_capture_contract.py`, `test_mcp_contract.py`, `py_compile`) were **not** re-executed this session — Bash approval was declined, same posture as R1 and the Phase 3 R2 review. Basis is direct source read + the provided GUI smoke artifact. Run the registered gates at commit time:
  ```sh
  python3 Tests/test_network_capture_contract.py
  python3 Tests/test_mcp_contract.py
  python3 scripts/smoke_real_world.py
  ```

## Blockers

None. F1/F2 (R1's required-before-close fixes) are landed and verified. F3–F6 are non-blocking.

## Phase 4 close decision

**Close Phase 4.** The evidence pillar is strengthened, honesty is tightened, the metadata-vs-artifact inconsistency is resolved, and the GUI smoke proves the path end-to-end. Before merging, run the three gates above so the close is backed by real non-GUI output, not inferred success (CLAUDE.md verification rule). Fold the F4 limitations-string alignment into the closing commit if cheap; defer F3's behavioral body-limit test only if it is tracked as the first item of the next track.

## Next track recommendation

1. **Stop broadening network capture.** Vision §6 + Hard Scope: proxy/HAR-grade/WebSocket/downloads stay a separate opt-in research spike — do not pull them into Phase 4 or the next slice. Hold the discipline already proven here: contract test + GUI smoke artifact + honest status tag.
2. **First item of the next track: pay down F3.** Add the behavioral body-truncation case (long non-sensitive body → assert preview ≤ N) so the acceptance criterion is true behaviorally rather than by echo. Cheap, directly serves "evidence over claims."
3. **Open Phase 5 deliberately and reconcile F6 first.** The real WKWebView tab/session/profile model is already shipping and smoke-proven; the next track should formalize single-WebView tab/session semantics under Phase 5 and correct the Gated/placeholder wording in `DEVELOPMENT_PHASES.md` in the same commit. Per Hard Scope, do not advance to true multi-tab/profile *isolation* until single-WebView semantics are documented and stable.
4. **Carry F4/F5 as housekeeping**, not a track of their own — resolve F4 opportunistically; leave F5 as a documented conservative-redaction tradeoff.
