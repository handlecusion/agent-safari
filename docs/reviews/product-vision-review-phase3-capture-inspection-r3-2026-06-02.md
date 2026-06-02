# Product-Vision Review (R3) — Phase 3 Capture/Inspection Slice After Wait/Preflight Expansion

- Date: 2026-06-02
- Reviewer persona: product-vision guardian (`docs/PRODUCT_VISION.md`, `docs/DEVELOPMENT_PHASES.md`)
- Prior reviews:
  - R1 `docs/reviews/product-vision-review-phase3-capture-inspection-2026-06-02.md` (PASS, 4 follow-ups)
  - R2 `docs/reviews/product-vision-review-phase3-capture-inspection-r2-2026-06-02.md` (PASS, 3/4 resolved)
- Scope of R3: verify the wait-predicate expansion (URL/title/visible) and full-page preflight scroll — the one acceptance criterion R1/R2 left open — and decide whether Phase 3 can be marked **Done** for the current capture/inspection reliability contract.

## VERDICT: PASS

The last open Phase 3 acceptance criterion (URL/title/visibility wait predicates, timeout-bounded, structured errors) is now implemented, wired end-to-end, contract-tested, and exercised in a real GUI smoke run. Full-page preflight scroll is implemented and produces real evidence (lazy content rendered + original scroll restored). No CDP/HAR/passkey/session-isolation overclaim was introduced or widened. Status text and spec are honest. **Phase 3 may be marked Done for the current capture/inspection reliability contract.** Five non-blocking findings below; none block closure.

## What Changed Since R2

R2 closed the capture/observe metadata slice and named wait-predicate expansion as the only remaining Phase 3 acceptance item. This slice adds:

1. `wait-for-url`, `wait-for-title`, `wait-for-visible` CLI commands (`Sources/AgentSafariCore/CommandRequest.swift:88-108`), each with default + `--timeout`/`--timeout-ms` parsing.
2. RPC dispatch for `waitForURL`/`waitForTitle`/`waitForVisible` (`Sources/AgentSafari/RPCHandler.swift:78-89`).
3. Wait implementations (`Sources/AgentSafari/BrowserControllerWaits.swift:34-75`) — substring match on `webView.url` / `webView.title`; visibility checks computed style + viewport-intersecting box. All route through `waitUntil` (`:103-116`), which throws `AgentSafariError.waitTimedOut` on deadline.
4. Full-page preflight scroll (`Sources/AgentSafari/BrowserControllerScreenshot.swift:174-197`) — steps a tall page through ~0.8×viewport increments, then restores the original scroll position; returns `preflightScrollCount`, surfaced in `screenshotFull` metadata.
5. MCP tool contracts for the three new waits (`mcp/agent_safari_mcp.py:45-47`) with daemon-side per-call timeouts.

## Alignment to Vision — clean

- **Eyes + hands, not breadth.** Wait predicates are squarely in the Priority 2 list (`PRODUCT_VISION.md:104-113`: "URL/title visibility predicates"). Preflight scroll improves screenshot fidelity (lazy/intersection content) — capture trust, not new surface area. Decision filter "more reliable at seeing/verifying?" → yes.
- **One control protocol preserved.** Swift remains canonical; MCP wrapper only declares the new tools and forwards `--timeout`. No logic in the wrapper.
- **Evidence over claims.** New predicates return structured success payloads and bounded structured timeout failures; preflight emits a real, inspectable `preflightScrollCount`.

## Overclaim / Honesty Check — clean

- `waitForURL`/`waitForTitle` are **substring** matches on the WebKit `url`/`title` — the MCP descriptions say "contains the supplied substring" (`agent_safari_mcp.py:45-46`). Honest, not full-match overclaim.
- `waitForVisible` is a computed-style + bounding-box viewport-intersection check — described as "exists and has a visible viewport-intersecting box" (`:47`). Matches the implementation; no "truly painted/clickable" overclaim.
- Preflight scroll is documented as giving lazy content "a chance to render" (`PRODUCT_SPEC.md:88`) — appropriately hedged, not a guarantee.
- Spec scope boundaries intact: CDP parity, default proxy/HAR, passkey, true session isolation all still disclaimed (`PRODUCT_SPEC.md:21,162-167`).

## Scope-Boundary Check — clean for this slice

No passkey, no default proxy/HAR, no CDP-parity claim, no hosted service, no extension. New wait predicates are narrow and documented (the explicit Phase 3 guardrail at `DEVELOPMENT_PHASES.md:161`: "Keep new wait predicates narrow ... do not expand into unsupported browser automation claims"). Respected.

## Status-Accuracy Check — accurate

- `DEVELOPMENT_PHASES.md:145` now marks Phase 3 **Done** for the current capture/inspection reliability contract, with further full-page rendering fidelity tagged as an enhancement. Given this R3 PASS, that status is now accurate (R1/R2 reviewed only the metadata slice; this review supplies the wait/preflight pass the "Done" mark presupposes).
- All four acceptance criteria (`:165-168`) are met with evidence:
  - structured screenshot metadata incl. `preflightScrollCount` — Done;
  - metadata contract-tested — Done;
  - full-page taller than viewport + preflight triggers lazy content while restoring scroll — Done (`222541`);
  - waits timeout-bounded + structured errors for URL/title/visible plus existing — Done (`222541`).

## Tests / Contract Coverage — present

- `Tests/AgentSafariCoreTests/CommandRequestTests.swift:102-114` — `commandRequestParsesWaitForUrlTitleAndVisible` locks parse → method/params for all three new commands.
- `Tests/AgentSafariCoreTests/MetadataTests.swift:25-27` — `wait-for-url/title/visible` included in the client-command parse matrix.
- `Tests/test_mcp_contract.py` — all three waits in `EXPECTED_TOOLS` (`:36-38`) and exact `cli`/`input` shapes asserted (`:104-106`).
- `Tests/test_capture_inspection_contract.py:29,74` — `preflightScrollCount` locked into the `screenshot_full` result contract.

## GUI Smoke Evidence — present and real

`.tmp/agent-safari-5-scenarios-20260602-222541/REPORT.md` — **5/5 PASS**. Verified from the raw step log in `data/scenario-results.json` (actual CLI JSON, not narration):

- `wait-for-url index.html` → `{matched:true, currentURL:...index.html, timeoutMs:5000}` (`ok:true`).
- `wait-for-title "Agent Safari Form Scenario"` → `{matched:true, currentTitle:..., timeoutMs:5000}`.
- `wait-for-visible #result` → `{visible:true, timeoutMs:5000}`.
- `wait-for-visible #does-not-exist --timeout 250` → `{ok:false, error.message:"Timed out after 250 ms"}` — bounded structured failure confirmed.
- `screenshot --full` → `preflightScrollCount:13`, `strategy:"single-rect"`, `pageHeight:7163` > `viewportHeight:720`; lazy probe `{loaded:30, last:"LAZY-SECTION-30", scrollY:0}` — preflight rendered all 30 lazy sections and restored scroll to 0.

## Non-Blocking Findings (R3)

1. **Wait-predicate result shapes are not contract-locked (only cli/input are).** `test_mcp_contract.py` asserts `cli`/`input` for `wait_for_url/title/visible` but not their `result` lists; `agent_safari_mcp.py:45-47` declares `matched`/`currentURL`/`currentTitle`/`visible` but no test pins them. Capture fields *are* locked (`test_capture_inspection_contract.py`). A future refactor could silently drop `currentURL`/`matched` without a red test. Recommend extending `test_agent_loop_tools_advertise_exact_cli_shapes_and_inputs` (or the capture contract) to assert the three wait `result` lists.
2. **No helper unit test guards the wait/preflight smoke assertions.** `Tests/test_smoke_real_world.py` unit-guards `screenshot_command_metadata` and `native_click_delivery`, but the URL/title/visible-wait and preflight-restore assertions live inline in `scripts/smoke_real_world.py:513-558` with no extracted, unit-tested helper. Lower regression safety than the capture-metadata path. Optional: factor a `wait_predicate_evidence`/`preflight_evidence` helper and unit-test it like the others.
3. **Tiled-scroll full-page path remains unexercised by smoke; scenario-2 purpose wording overstates.** The `long.html` fixture is 1280×7163 ≈ 9.16M px, below the 16M single-snapshot threshold (`BrowserControllerScreenshot.swift:35`), so the run used `strategy:"single-rect"`. Scenario 2's purpose text says it validates the "tiled screenshot 경로" (tiled path), but the tiled branch (`:62-81`) did not execute. Either correct the purpose string to "single-rect + preflight" or add a fixture large enough (>16M px or width>viewport) to actually drive the tiled path. This is the explicitly-deferred "full-page stitching robustness" enhancement (`DEVELOPMENT_PHASES.md:160`) — fine to defer the path, but fix the inaccurate evidence label.
4. **Carryover (R1 #3 / R2 #4): Phase 5 "Gated" vs shipped real tabs — STILL OPEN, tracking-only.** `DEVELOPMENT_PHASES.md:189-208` still marks Phase 5 **Gated**/"placeholder ... commands" while smoke scenario 4 runs a real `WKWebView` tab model as a `ci-compatible` gate (`REPORT.md:118`). Pre-existing, not introduced by this slice. With Phase 3 now closing and the real-tab gate riding in the CI-compatible matrix, reconcile the Phase 5 wording the next time Phase 5 is touched so "Gated" stays honest.
5. **Tests not executed in this review session (Bash approval declined), as in R1/R2.** Verdict rests on static field-match plus the raw CLI JSON in `222541/data/scenario-results.json`, which is genuine command output (stronger than static-only). Run the registered gates at commit time: `swift test`, `python3 Tests/test_capture_inspection_contract.py`, `python3 Tests/test_mcp_contract.py`, `python3 Tests/test_smoke_real_world.py`.

## Blockers

None.

## Phase 3 Closure Decision

**Phase 3 — Capture and Inspection Metadata: can be marked Done for the current capture/inspection reliability contract.** All four acceptance criteria are met with real evidence; status text and spec are honest; remaining items (tiled-stitching robustness, fixed-header/high-DPI fidelity) are correctly tagged as enhancements, not blockers. Findings 1–3 are quality hardening that should be folded into the closing commit or the next capture touch; findings 4–5 are carry-forward/process.

## Next Track Guidance

- Do not drift into Phase 4 (network hardening) or Phase 5 (session/tab model) on the back of this slice. Phase 5 is still Gated; reconcile its wording (finding 4) only when that phase is actually opened.
- If/when full-page fidelity is revisited, lead with a fixture that genuinely crosses the tiled threshold (finding 3) so the tiled path gets real evidence, and lock the wait-predicate result shapes (finding 1) under the same evidence discipline used for capture metadata.
