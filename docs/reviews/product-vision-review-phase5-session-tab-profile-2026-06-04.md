# Product-Vision Review — Phase 5 Session/Tab/Profile Contract

- Reviewer persona: product-vision guardian (`docs/PRODUCT_VISION.md`, `docs/PRODUCT_SPEC.md`)
- Scope: Phase 5 close for the current modeled daemon session/tab/profile contract
- Review mode: read-only subagent review after implementation fixes
- Evidence basis: current working-tree diff, Phase 5 docs, Swift session/tab code, MCP tool contract, contract tests, CLI smoke, GUI smoke report `.tmp/agent-safari-5-scenarios-20260604-154342/REPORT.md`

## VERDICT: PASS — Phase 5 closed for the modeled contract

Phase 5 now closes as the current **single-daemon, single-window, modeled WKWebView tab/session/profile contract**, not as true multi-profile, multi-window, or browser multi-target isolation.

The closure is aligned with the product vision: it strengthens agent reliability and failure evidence while keeping unsupported isolation claims out of the public surface.

## Confirmed fixes

1. `DEVELOPMENT_PHASES.md` no longer says Phase 5 is `Gated` or placeholder-only. It documents the current modeled contract and future isolation work separately.
2. `PROFILE_PERSISTENCE.md` defines session, tab, window, profile, artifact scope, and MCP socket scope.
3. `PRODUCT_SPEC.md` and `PRODUCT_VISION.md` keep true profile/session isolation as future work beyond the current one-daemon modeled tab contract.
4. `tab-close` now returns aligned result fields for success and last-tab refusal: `id`, `tabId`, `closed`, `activeTabId`, and `reason`.
5. MCP `status` now advertises the actual Swift result shape: `url`, `title`, `loading`, `sessionId`, `tabId`.
6. `scripts/smoke_real_world.py` scenario 4 now asserts profile metadata, `persistent: false`, `dataStore: nonPersistent`, active-tab uniqueness after new/switch, `tab-close`, last-tab refusal, and post-close session state.
7. `Tests/test_session_profile_contract.py` pins Phase 5 code/docs/MCP boundaries against future drift.

## Verification

- `swift test` — PASS
- `python3 -m py_compile mcp/agent_safari_mcp.py scripts/smoke_real_world.py Tests/test_session_profile_contract.py Tests/test_mcp_contract.py Tests/test_smoke_real_world.py Tests/test_network_capture_contract.py` — PASS
- `python3 Tests/test_capture_inspection_contract.py` — PASS
- `python3 Tests/test_agentic_refs_contract.py` — PASS
- `python3 Tests/test_browser_chrome_contract.py` — PASS
- `python3 Tests/test_network_capture_contract.py` — PASS
- `python3 Tests/test_session_profile_contract.py` — PASS
- `python3 Tests/test_mcp_contract.py` — PASS
- `python3 Tests/test_smoke_real_world.py` — PASS
- `git diff --check` — PASS
- `bash -n scripts/*.sh` — PASS
- `bash scripts/smoke_cli.sh` — PASS
- `python3 scripts/smoke_real_world.py --skip-build` — PASS, report `.tmp/agent-safari-5-scenarios-20260604-154342/REPORT.md`

## Residual risks

- Historical review files still mention the old Phase 5 placeholder blocker; those are archival, not current product docs.
- Network capture state is currently controller-global and resets on tab creation/switch. Cross-tab network semantics remain future work unless explicitly documented and tested in a later phase.
- Named `--profile` values still do not create named cookie/cache/storage directories. This is documented and remains future work.
