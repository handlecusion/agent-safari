# Product-Vision Review R3 (Final) — Phase 4 Network Capture Hardening Slice

- Date: 2026-06-02
- Reviewer persona: product-vision guardian (`docs/PRODUCT_VISION.md`, `docs/PRODUCT_SPEC.md`, `docs/DEVELOPMENT_PHASES.md`)
- Scope: final re-review of the uncommitted Phase 4 network-capture-hardening slice after F1/F2 (closed in R2) plus the two follow-ups R2 named for the next track — F3 (body-preview behavioral smoke) and F4 (limitation parity)
- Mandate: confirm F3/F4 landed without introducing CDP/HAR/proxy overclaim, and give a final PASS/BLOCKER on closing Phase 4
- Evidence basis: direct read of the working-tree diff for `Sources/AgentSafari/BrowserControllerNetwork.swift`, `scripts/smoke_real_world.py`, `Tests/test_network_capture_contract.py`, `Tests/test_mcp_contract.py`, `mcp/agent_safari_mcp.py`, `docs/PRODUCT_SPEC.md`, `docs/DEVELOPMENT_PHASES.md`, `CLAUDE.md`; new GUI smoke report `.tmp/agent-safari-5-scenarios-20260602-230011/REPORT.md` (5/5 PASS)

## VERDICT: PASS — Phase 4 may close

F1/F2 (R2's required-before-close fixes) remain landed. The two carry-overs R2 routed to the next track are now both fixed in this slice:

- **F3** — body-preview truncation is now proven behaviorally, not echoed. A 200-byte non-sensitive POST body is asserted to come back as exactly `'n' * 80`.
- **F4** — the result-map `limitations` string and the artifact `limitations` array are now the **same 8 items**; the previously-dropped `"no request/response headers for parser-driven resources"` is restored to the result string.

The slice stays squarely on-vision: it strengthens the **Evidence** pillar and **tightens honesty**. No CDP/HAR/proxy parity claim was added or widened — the new metadata fields are all honest descriptors and the limitations list grew *more* explicit (`not full HAR completeness`, `no default proxy capture`, `no downloads`). **Phase 4 can be declared closed.**

Residual items below are housekeeping, not blockers.

## R2 carry-overs — both confirmed fixed

### F3 (body-preview limit not behaviorally verified) — FIXED
- Fixture now issues a third request — `POST /post.json` with `body: 'n'.repeat(200)`, a non-sensitive 200-byte body (`scripts/smoke_real_world.py:479`).
- Smoke asserts the stored preview is trimmed to the bound, not merely that the bound is echoed: `if long_preview != 'n' * 80: raise AssertionError(...)` (`smoke_real_world.py:586-588`). Because the body contains no token matching the sensitive pattern, redaction passes it through and the `bodyPreviewBytes=80` trim is what's under test. This is real truncation proof.
- The echo check is still kept as a secondary assertion (`bodyPreviewBytes == '80'`, `:590-591`), now alongside the behavioral one.
- Smoke run confirms the new request landed: scenario 3 reports `eventCount: 3`, `types: ["fetch", "fetch", "xhr"]` (`230011/REPORT.md:69-70`) — up from the two-event run in R2's `225601`. 5/5 PASS means the truncation assertion held end-to-end.

### F4 (limitations list differed between representations) — FIXED
- Artifact array (`BrowserControllerNetwork.swift:149`) and result-map string (`:206`) now carry the **identical 8 limitations**, including `"no request/response headers for parser-driven resources"`, which the result string previously dropped.
- Both representations now also gained `no downloads`, `not full HAR completeness`, and `no default proxy capture`, so the honest scope is stated the same way in the artifact, the CLI/MCP result, and the docs.
- Contract test pins the 7 honest phrases against the source and pins the count fields shut (`Tests/test_network_capture_contract.py:35-52`). See residual note R1 below: the contract still does not assert the two representations are byte-for-byte equal, nor does it pin the restored headers phrase, so F4 parity is correct in code but not regression-locked.

## Honesty / scope — clean (core mandate)

- **No overclaim introduced.** `schema: "har-like"` (not `"har"`), `captureType: "fetch-xhr-js-instrumentation"`, `redacted: true`, and the now-8-item `limitations` hold the line against CDP/HAR/proxy parity. The new result fields (`captureType`, `limitations`, `bodyPreviewBytes`, `maxEntries`, `entryCount`, `eventCount`, `resourceTimingCount`, `redactionPolicy`) are descriptors of what was captured and what was *not* — they narrow claims, they do not widen them.
- **Redaction still proven, not asserted.** Smoke scenario 3 injects `Auth header: Token should-redact`, `X-Redact-Token: should-redact-token`, and body `sensitive-field: should-redact-sensitive-field`, then asserts `should-redact` is absent from the whole export text (`smoke_real_world.py:580-581`). Behavioral, against live secrets.
- **New body-preview redaction is conservative.** `redactBodyPreview` blanks any preview matching the sensitive pattern to `[REDACTED]` (`BrowserControllerNetwork.swift:52`). Correctly lossy-toward-safe, consistent with the Vision's redaction default.
- **Doc/code alignment holds and improved.** `PRODUCT_SPEC.md` now states the PerformanceResourceTiming inclusion, the no-HAR/no-proxy/no-downloads boundary, and the body-preview/redaction requirement (`:93-95,153`). `DEVELOPMENT_PHASES.md` Phase 4 acceptance criteria now require contract-tested schema and result metadata exposure (`:184-188`). `test_phase4_docs_state_current_scope_boundaries` pins these phrases (`test_network_capture_contract.py:92-106`).

## Remaining non-blocking items

- **R1 — F4 parity is not regression-locked.** The contract test asserts each honest phrase is *present in source* (`test_network_capture_contract.py:32-45`) but does not assert the result-map string and the artifact array are the same set, and its `required_limitations` list (7 items) still omits `"no request/response headers for parser-driven resources"`. The two lists are equal today; nothing stops them drifting apart again. Fold a parity assertion (and the headers phrase) into the closing commit so F4 cannot silently regress.
- **R2-residual — `redactionPolicy` wording differs between representations.** Artifact says `"...are redacted; body previews are bounded by bodyPreviewBytes when provided"` (`BrowserControllerNetwork.swift:154`); result map says `"sensitive headers and sensitive body previews redacted"` (`:209`). Same meaning, cosmetic mismatch — unlike F4 this is not a content/count discrepancy. Align opportunistically; not a close blocker.
- **R3 — trim-before-redact straddle edge (minor, conservative-leaning).** `redactBodyPreview(trimBody(value))` trims to N bytes first, then pattern-matches the *trimmed* preview. A sensitive token split across the N-byte boundary (e.g. `...passw` at the tail) would not match and a partial token could remain. This is a narrow edge and fails toward *less* exposure than the untrimmed body, but a key-aware or pre-trim match would be tighter. Note for the F5 redaction-hardening backlog, not this phase.
- **F5 (carry-over) — `redactBodyPreview` nukes the whole preview on any match.** Unchanged. Correctly conservative per Vision; lossy for evidence. Future key-level redaction would preserve more signal. No action this phase.
- **F6 (carry-over) — Phase 5 placeholder wording still contradicts shipped tab behavior.** Smoke scenario 4 PASS exercises a real `WKWebView` tab model (`tab-new`/`tab-switch`, `tabCount: 2`, nonPersistent session — `230011/REPORT.md:84-86`), stronger than the "placeholder" wording. This slice does not touch Phase 5, so the gap is neither introduced nor worsened. Reconcile when a commit next touches Phase 5.
- **Process — `DEVELOPMENT_PHASES.md` Phase 4 status reads `Active`, not closed (`:172`).** Honest while the slice is in review. Once this PASS is acted on, the closing commit should flip Phase 4 to its done/closed state so the roadmap reflects the close decision.

## Evidence

- **Static review (this session):** read the full working-tree diff. Confirmed: distinct artifact-sourced `entryCount`/`eventCount`/`resourceTimingCount` in the result map (no `"see-artifact"` literal); 8-item limitations identical in artifact array and result string; new behavioral body-truncation case and leak/limitation/metadata assertions in `smoke_real_world.py`; MCP `network_export` result contract and both contract tests carry the Phase 4 result fields; docs state the honest scope.
- **GUI smoke `230011/REPORT.md`:** 5/5 PASS. Scenario 3 PASS with `eventCount: 3` (the added POST), `resourceTimingCount: 2`, export written to `data/03_network.har.json`. Because the modified `smoke_real_world.py` carries the truncation + leak + limitation + metadata assertions, this PASS is runtime proof the honest-metadata, body-truncation, and redaction paths all work end-to-end against injected secrets and an over-length body.
- **Caveat (verification gap):** the non-GUI contract gates were **not** executed this session — Bash approval was declined (same posture as R1, R2, and Phase 3 R2). The PASS rests on direct source read plus the provided GUI smoke artifact. The closing commit MUST run the registered gates so the close is backed by real output, not inferred success (CLAUDE.md verification rule):
  ```sh
  python3 -m py_compile mcp/agent_safari_mcp.py scripts/smoke_real_world.py Tests/test_network_capture_contract.py Tests/test_mcp_contract.py
  python3 Tests/test_network_capture_contract.py
  python3 Tests/test_mcp_contract.py
  python3 scripts/smoke_real_world.py
  ```
  Note the smoke report could also surface the trimmed preview length explicitly (it currently only prints `eventCount`/`types`); the truncation evidence today is the PASS of the assertion, not a printed value. Optional auditability improvement.

## Blockers

None. F1/F2 stay closed; F3 (behavioral body-preview truncation) and F4 (limitation parity) are landed and verified by source read + GUI smoke. R1/R2-residual/R3/F5/F6 and the status-line flip are non-blocking housekeeping.

## Phase 4 close decision

**Close Phase 4.** The Evidence pillar is strengthened, honesty is tightened and now stated identically across artifact/result/docs, the body-preview limit is behaviorally proven, and the GUI smoke proves the path end-to-end against live secrets. In the closing commit: (1) run the four gates above so the close carries real non-GUI output; (2) flip Phase 4 status from `Active` to closed in `DEVELOPMENT_PHASES.md`; (3) add the F4 parity assertion + restored headers phrase to `test_network_capture_contract.py` so the now-correct lists cannot drift.

## Next track recommendation

1. **Stop broadening network capture.** Vision §6 + Hard Scope: proxy/HAR-grade/WebSocket/downloads stay a separate opt-in research spike — do not pull them into a follow-on slice. The discipline proven here (contract test + GUI smoke artifact + honest status tag) is the bar; hold it.
2. **Open Phase 5 deliberately and reconcile F6 first.** The real WKWebView tab/session/profile model is already shipping and smoke-proven (scenario 4). The next track should formalize single-WebView tab/session semantics under Phase 5 and correct the placeholder wording in `DEVELOPMENT_PHASES.md` in the same commit. Per Hard Scope, do not advance to true multi-tab/profile *isolation* until single-WebView semantics are documented and stable.
3. **Carry redaction hardening (F5 + R3 straddle edge) as backlog**, not a track of its own. If/when key-level redaction is taken up, it both preserves more evidence signal (F5) and closes the trim-before-match edge (R3). Until then the conservative blank-on-match behavior is the documented tradeoff.
4. **Housekeeping in-flight:** resolve the `redactionPolicy` wording mismatch (R2-residual) opportunistically; it is cosmetic.
