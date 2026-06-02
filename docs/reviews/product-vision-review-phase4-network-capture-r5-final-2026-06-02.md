# Product-Vision Review R5 (Final Sanity) — Phase 4 Network Capture Hardening

- Date: 2026-06-02
- Reviewer persona: product-vision guardian (`docs/PRODUCT_VISION.md`, `docs/PRODUCT_SPEC.md`, `docs/DEVELOPMENT_PHASES.md`)
- Scope: final sanity pass after the three post-R4 actions — (1) parity **set-equality** assertion, (2) `redactionPolicy` wording alignment, (3) report-pointer fix to the latest smoke run — and confirmation that local gates ran this session
- Evidence basis: `Sources/AgentSafari/BrowserControllerNetwork.swift`, `Tests/test_network_capture_contract.py`, `docs/DEVELOPMENT_PHASES.md`; GUI smoke `.tmp/agent-safari-5-scenarios-20260602-230730/REPORT.md` (5/5 PASS); local gates reported run: `py_compile`, `Tests/test_network_capture_contract.py`, `swift test`, `scripts/smoke_real_world.py --skip-build`; prior review `docs/reviews/...-r4-close-2026-06-02.md`

## VERDICT: PASS — Phase 4 closed, all R4 residuals cleared

The three R4-tracked code/doc residuals all landed, the carried verification gap is closed by this session's local gates, and no new overclaim was introduced. Phase 4 is honestly done. Nothing blocks.

## R4 residuals → resolved

1. **R1 (parity set-equality) — resolved.** `test_network_capture_contract.py:68-76` now parses the artifact array and the result-map string and asserts `artifact_items == result_items` (line 76). The two limitation representations can no longer drift silently — presence-in-source was upgraded to equality. The 8-item list (incl. restored `no request/response headers for parser-driven resources`) stays separately pinned (`:36-47`).
2. **R2-residual (`redactionPolicy` wording) — resolved.** Artifact (`BrowserControllerNetwork.swift:155`) and result map (`:211`) are now the **identical** string: `sensitive headers and sensitive body previews redacted; body previews are bounded by bodyPreviewBytes when provided`. Cosmetic divergence gone.
3. **R-doc (report pointer) — resolved.** `DEVELOPMENT_PHASES.md:187` now cites `.tmp/...-230730/REPORT.md` — the run this close actually rests on — instead of the stale `230011`/`230357` pointers.

## Verification gap (R4 carried) — closed

R1–R4 PASSes rested on source-read + GUI smoke artifact because Bash gates were declined those sessions. This session the registered non-GUI gates ran: `py_compile`, `test_network_capture_contract.py`, `swift test`, plus `smoke_real_world.py --skip-build`. Close now carries real output, satisfying the CLAUDE.md "record real verification, not inferred success" rule.

## Honesty / scope — clean

- No CDP/HAR/proxy parity. 8-item limitations identical across artifact (`:149`), result map (`:205`), and docs (`DEVELOPMENT_PHASES.md:179`). `captureType: fetch-xhr-js-instrumentation`, `schema: har-like`, `redacted: true` — all narrow claims.
- Smoke `230730` 5/5 PASS. Scenario 3: `eventCount: 3`, `types: ["fetch","fetch","xhr"]`, `resourceTimingCount: 2`, export `data/03_network.har.json`. Report Notes restate the limitation (resource-timing entries carry no headers/body) — runtime evidence matches the contract, not a wider claim.
- Evidence pillar strengthened; no breadth added.

## Non-blocking residuals (carried to backlog)

- **F5 — redaction edges.** Trim-before-match straddle and whole-preview blank-on-match remain. Conservative-toward-safe; defer to an F5 key-level redaction track.
- **F6 — Phase 5 placeholder wording.** Phase 5 is `Gated`; placeholder language still lags the shipped WKWebView tab model (smoke scenario 4: `tabCount: 2`, `dataStore: nonPersistent`). Reconcile in the same commit that opens Phase 5.

## Blockers

None.

## Next track

1. **Stop broadening network capture.** Proxy/HAR-grade/WebSocket/downloads stay a separate opt-in research spike per Hard Scope. The discipline held here — set-equality contract + GUI smoke artifact + honest status tag + run gates — is the bar to keep.
2. **Open Phase 5 deliberately; fix F6 first.** Single-WebView tab/session/profile semantics are shipping and smoke-proven; formalize and correct the placeholder wording in one commit. Do not advance to true multi-tab/profile isolation before single-WebView semantics are documented and stable.
3. **Backlog, not a track:** F5 redaction hardening — fold into an adjacent commit opportunistically.
