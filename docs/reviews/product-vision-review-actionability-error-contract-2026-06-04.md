# Product vision review: actionability error contract

Date: 2026-06-04

Reviewer persona: Claude Code-style product-vision guardian aligned to `docs/PRODUCT_VISION.md`.

## Decision

Next slice after Phase 5 should be action result/error contract hardening, before Phase 6 productization.

Rationale:

- It strengthens hands and failure explanations, which are core product promises.
- It turns click/fill failure handling from mostly human-readable JavaScript exception strings into machine-readable actionability/native-input codes.
- It avoids broadening into CDP/HAR/passkey/profile-isolation claims.

## Recommended scope

Implement stable JSON-RPC `error.code` values for current actionability/native-input classes:

- `actionability_stale_ref`
- `actionability_refs_unavailable`
- `actionability_missing_selector`
- `actionability_disabled`
- `actionability_hidden`
- `actionability_off_viewport`
- `actionability_occluded`
- `native_click_unverified`
- `native_input_failed`

Also align MCP advertised result shapes with the Swift CLI:

- `click` includes native/fallback, coordinate, viewport, bounds, and scroll metadata.
- `fill` returns `selector` and `value`.

## Acceptance gates

- `swift test`
- `python3 Tests/test_agentic_refs_contract.py`
- `python3 Tests/test_mcp_contract.py`
- `python3 Tests/test_smoke_real_world.py`
- Python compile checks for MCP, smoke, and tests.
- `bash scripts/smoke_cli.sh`
- Local GUI smoke when available: `python3 scripts/smoke_real_world.py --skip-build`

## Overclaim checks

- Do not claim strict native delivery success; it remains environment-gated.
- Treat `document.elementFromPoint` as center-hit evidence, not a universal clickability proof.
- Do not add CDP/HAR/passkey/true profile isolation claims.
- Keep Phase 5 one-daemon/session/tab/profile boundaries intact.
