# Product-Vision Review R4 (Close Verification) — Phase 4 Network Capture Hardening

- Date: 2026-06-02
- Reviewer persona: product-vision guardian (`docs/PRODUCT_VISION.md`, `docs/PRODUCT_SPEC.md`, `docs/DEVELOPMENT_PHASES.md`)
- Scope: verify the final Phase 4 **close** state after the two post-R3 actions — (1) status flip `Active` → Done in `DEVELOPMENT_PHASES.md`, (2) F4 limitation-parity update to `Tests/test_network_capture_contract.py`
- Evidence basis: working-tree diff (`Sources/AgentSafari/BrowserControllerNetwork.swift`, `mcp/agent_safari_mcp.py`, `Tests/test_mcp_contract.py`, `Tests/test_network_capture_contract.py`, `docs/PRODUCT_SPEC.md`, `docs/DEVELOPMENT_PHASES.md`, `CLAUDE.md`, `scripts/smoke_real_world.py`); GUI smoke `.tmp/agent-safari-5-scenarios-20260602-230357/REPORT.md` (5/5 PASS); prior review `docs/reviews/...-r3-2026-06-02.md`

## VERDICT: PASS — Phase 4 close confirmed

The two close actions R3 required both landed, no new overclaim, Evidence pillar still strengthened. No blockers. Residuals below are housekeeping.

## Close actions verified

1. **Status flip — done.** `DEVELOPMENT_PHASES.md:172` now reads `Product-vision reviewed and Done for the current network capture hardening contract`, matching the Phase 3 closure wording. The R3 process item (status still `Active`) is resolved. Acceptance criteria flipped to `Done` with evidence pointers (`:184-189`).
2. **F4 parity test update — done (partial).** `test_network_capture_contract.py:35-44` `required_limitations` is now the **8-item** list and pins the previously-omitted `"no request/response headers for parser-driven resources"` (`:38`). R3's R1 ask — regression-pin the restored headers phrase — is landed. The count fields stay pinned (`:48-53`). See R1-residual: a true set-equality assertion between the artifact array and the result-map string is still not present (each phrase is checked `in source`, not that the two representations are equal), so they could still drift if one copy drops a phrase the other keeps. Correct in code today; not fully parity-locked.

## Honesty / scope — clean

- No CDP/HAR/proxy parity introduced. `schema: "har-like"`, `captureType: "fetch-xhr-js-instrumentation"`, `redacted: true`, 8-item limitations identical across artifact array (`BrowserControllerNetwork.swift:149`), result-map string (`:206`), and docs.
- New result fields (`captureType`, `limitations`, `bodyPreviewBytes`, `maxEntries`, `entryCount`, `eventCount`, `resourceTimingCount`, `redactionPolicy`) narrow claims, not widen. `network_export` MCP/CLI result contract carries them (`mcp/agent_safari_mcp.py:52`, `Tests/test_mcp_contract.py:108`).
- Redaction conservative: sensitive headers redacted, `redactBodyPreview` blanks any matching preview to `[REDACTED]`, body bounded by `bodyPreviewBytes`.

## Verification checked

- **Static (this session):** read full working-tree diff + the four target artifacts. Confirmed status flip, 8-item F4 parity list with restored headers phrase, identical limitations across artifact/result/docs, no `"see-artifact"` literal, distinct artifact-sourced count fields.
- **GUI smoke `230357/REPORT.md`:** 5/5 PASS. Scenario 3 `eventCount: 3`, `types: ["fetch","fetch","xhr"]`, `resourceTimingCount: 2`, export written to `data/03_network.har.json`. Because the modified `smoke_real_world.py` carries the leak / limitation / 80-byte-truncation / metadata assertions, this PASS is runtime proof against injected secrets and an over-length body.
- **Verification gap (carried):** non-GUI contract gates were **not** executed this session — Bash approval was declined (same posture as R1/R2/R3). PASS rests on source read + the GUI smoke artifact. The closing commit MUST run the registered gates so the close carries real output, not inferred success (CLAUDE.md rule):
  ```sh
  python3 -m py_compile mcp/agent_safari_mcp.py scripts/smoke_real_world.py Tests/test_network_capture_contract.py Tests/test_mcp_contract.py
  python3 Tests/test_network_capture_contract.py
  python3 Tests/test_mcp_contract.py
  swift test
  python3 scripts/smoke_real_world.py
  ```

## Non-blocking residuals

- **R1 (carried) — F4 parity not fully regression-locked.** Restored headers phrase is now pinned, but the contract still asserts presence-in-source, not artifact-array == result-string equality. Fold a set-equality assertion in opportunistically so the two copies cannot diverge.
- **R-doc — report pointer mismatch.** `DEVELOPMENT_PHASES.md:187` cites `.tmp/...-230011/REPORT.md` as body-preview evidence, but the designated final close run is `230357`. Both are 5/5 PASS with `eventCount: 3`; cosmetic, but point the acceptance criterion at the report this close actually rests on.
- **R2-residual — `redactionPolicy` wording differs** between artifact (`:154`) and result map (`:209`). Same meaning, cosmetic.
- **R3 / F5 (carried) — redaction edges.** Trim-before-match straddle and whole-preview blank-on-match remain. Conservative-toward-safe; backlog for an F5 key-level redaction track, not this phase.
- **F6 (carried) — Phase 5 placeholder wording** still lags the shipped WKWebView tab model (smoke scenario 4: `tabCount: 2`, nonPersistent). Reconcile when a commit next touches Phase 5; not introduced here.

## Blockers

None.

## Next track

1. **Stop broadening network capture.** Proxy/HAR-grade/WebSocket/downloads stay a separate opt-in research spike per Hard Scope. The bar set here — contract test + GUI smoke artifact + honest status tag — is the discipline to hold.
2. **Open Phase 5 deliberately; reconcile F6 first.** Single-WebView tab/session/profile semantics are shipping and smoke-proven; formalize them under Phase 5 and fix the placeholder wording in the same commit. Do not advance to true multi-tab/profile isolation before single-WebView semantics are documented and stable.
3. **Backlog, not a track:** F4 set-equality assertion (R1), `redactionPolicy` wording (R2-residual), report-pointer fix (R-doc), and redaction hardening (F5 + R3) — fold into adjacent commits opportunistically.
</content>
</invoke>
