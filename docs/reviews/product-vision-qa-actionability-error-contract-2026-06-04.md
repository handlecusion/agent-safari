# Product vision QA: actionability error contract

Date: 2026-06-04

Reviewer persona: Claude Code-style product-vision QA reviewer aligned to `docs/PRODUCT_VISION.md`.

## Result

PASS.

## Findings addressed

Initial review found one blocking contract mismatch:

- MCP `fill` advertised no inputs while the actual tool requires `selector` and `value`.

Fix:

- `mcp/agent_safari_mcp.py` now advertises `input: ["selector", "value"]`.
- `Tests/test_mcp_contract.py` locks the same shape.

The review also requested stronger evidence for the new actionability taxonomy and click metadata.

Fix:

- `scripts/smoke_real_world.py` scenario 5 now runtime-verifies:
  - `actionability_refs_unavailable`
  - `actionability_missing_selector`
  - `actionability_disabled`
  - `actionability_hidden`
  - `actionability_off_viewport`
  - `actionability_stale_ref`
  - `actionability_occluded`
- Native fallback metadata now requires `nativeError` and `nativeErrorCode`.
- Click smoke metadata now requires advertised coordinate, bounds, viewport, and scroll fields.

## Evidence

- `swift test`
- `python3 Tests/test_agentic_refs_contract.py`
- `python3 Tests/test_mcp_contract.py`
- `python3 Tests/test_smoke_real_world.py`
- `bash scripts/smoke_cli.sh`
- `python3 scripts/smoke_real_world.py --skip-build` -> `.tmp/agent-safari-5-scenarios-20260604-161658/REPORT.md`
- `AGENT_SAFARI_STRICT_NATIVE=1 python3 scripts/smoke_real_world.py --skip-build` -> expected environment-gated failure with JSON-RPC `error.code: native_click_unverified`

## Residual risk

`native_input_failed` is mapped and source-contract tested, but this environment does not provide a reliable runtime fixture for forcing CGEvent/NSEvent creation failure.
