# Product-Vision Review — Phase 3 Capture/Inspection Metadata Slice

- Date: 2026-06-02
- Reviewer persona: product-vision guardian (`docs/PRODUCT_VISION.md`, `docs/DEVELOPMENT_PHASES.md`)
- Scope reviewed (uncommitted):
  - `Sources/AgentSafari/BrowserControllerScreenshot.swift` — screenshot result metadata
  - `Sources/AgentSafari/BrowserControllerSession.swift` — `observe` metadata
  - `mcp/agent_safari_mcp.py` — `screenshot*` / `observe` tool contracts
  - `Tests/test_capture_inspection_contract.py` (new)
  - `Tests/test_smoke_real_world.py`, `scripts/smoke_real_world.py`
  - `docs/PRODUCT_SPEC.md`, `docs/DEVELOPMENT_PHASES.md`

## VERDICT: PASS

The slice is on the Phase 3 (Priority 2) critical path — richer page state and screenshot context — and stays inside scope. No CDP/HAR/passkey/session-isolation overclaim was introduced. Status text is honest about what closed and what remains. Real GUI evidence exists. No blockers; four non-blocking follow-ups below.

## Alignment to Vision

- **Eyes strengthened, not breadth.** Screenshot metadata (viewport/page size, scale, tileCount, strategy, warnings, outputPath) and `observe` state (loadState, pendingNetworkCount, selectedText, viewport/page size, activeElementSelector) give agents better state awareness — directly the Priority 2 list in `PRODUCT_VISION.md`. Decision filter "does this make an agent more reliable at seeing/verifying?" → yes.
- **One control protocol preserved.** Swift remains canonical; MCP `TOOL_CONTRACTS` only declares the new result fields (thin wrapper, no logic).
- **Evidence over claims.** New contract test locks the fields; smoke asserts per-capture metadata and full-page-taller-than-viewport via both PNG dims and reported `pageHeight > viewportHeight`.

## Overclaim / Honesty Check — clean

- `scale` = `window.backingScaleFactor` (real), `tileCount` reflects actual tiling path, `warnings` is a JSON array.
- `observe.loadState` = `document.readyState` — a JS load-state signal, not a network-idle guarantee. Not overclaimed.
- `pendingNetworkCount` reads `window.__agentSafariNetworkPending`, which is genuinely incremented/decremented in `BrowserControllerNetwork.swift:223-224`; returns 0 when capture inactive. Honest.
- Docs continue to disclaim CDP/HAR parity (`PRODUCT_SPEC.md:21`, `161`).

## Scope-Boundary Check — clean for this slice

No passkey, no default proxy/HAR, no CDP-parity claim, no hosted service, no extension. Tab/session work is **not** part of this slice (pre-existing surface). See follow-up 3 for a latent tracking note.

## Status-Accuracy Check — accurate

`DEVELOPMENT_PHASES.md` Phase 3 marked **Active**, current checkpoint "closes the capture/observe metadata slice; wait predicate expansion remains." Matches the code: capture+observe metadata landed; no URL/title/visibility wait predicate added. Acceptance criteria honestly tagged "Done for current metadata fields" while leaving wait expansion pending. Full-page smoke claim cites `.tmp/agent-safari-5-scenarios-20260602-220806/REPORT.md` — verified present, **5/5 PASS**.

## Tests / Smoke Evidence — present

- `test_capture_inspection_contract.py`: screenshot fields, observe fields, MCP contract subset — all assertions match current source (verified by static inspection).
- `test_smoke_real_world.py`: adds `test_screenshot_command_metadata_requires_phase3_fields`.
- `scripts/smoke_real_world.py`: validates `screenshot_command_metadata` on every capture; records `observe` before/after in scenario 5 evidence.
- GUI evidence: `220806` REPORT.md, 5/5 PASS.

> Note: contract tests were not re-executed in this review session (Bash approval declined); verdict rests on static field-match inspection plus the existing 220806 GUI run. Recommend a clean `python3 Tests/test_capture_inspection_contract.py` run at commit time.

## Non-Blocking Follow-ups

1. **Register the new contract test in the gate list.** `CLAUDE.md` quality-gate `py_compile` + explicit-run set does not include `Tests/test_capture_inspection_contract.py`. An unregistered contract test can silently rot. Add it in the same commit.
2. **Single-rect "warning" is informational, not a warning.** `BrowserControllerScreenshot.swift:48` pushes `"single-rect full-page capture did not need tiled-scroll fallback"` into `warnings`. Agents parsing `warnings` as problems may misread. Move to a `notes`/`strategyNote` field or drop it.
3. **Phase 5 gating vs. shipped tab model (tracking only).** Smoke scenario 4 exercises a real `WKWebView` tab model while `DEVELOPMENT_PHASES.md` Phase 5 (session/tab/profile) is **Gated**. Not introduced by this slice, but the gap between "Gated" and shipped real tabs should be reconciled in the Phase 5 section so status stays honest.
4. **MCP `observe` contract field list is a partial subset.** `agent_safari_mcp.py:26` lists `activeElementTag` + `activeElementSelector` but omits `activeElementType/Name/Id` that Swift returns. Harmless (contract is a min-subset, tests pass) but align for documentation accuracy.

## Next Track Guidance

Proceed to the remaining Phase 3 items to close the phase:

1. Wait-predicate expansion — URL, title, visibility — timeout-bounded, structured errors (the one acceptance criterion still open).
2. Full-page stitching robustness for fixed headers / lazy-loaded / high-DPI beyond the current single-rect/tiled evidence.

Do **not** drift into Phase 4 network or Phase 5 session work until the wait-predicate slice closes Phase 3. Keep the same evidence discipline: contract test + GUI smoke artifact + honest status tag.
