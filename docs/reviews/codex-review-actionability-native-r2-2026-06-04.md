# Codex review: actionability/native R2

Date: 2026-06-04

Reviewer: Codex `cx` read-only reviewer aligned to `docs/PRODUCT_VISION.md`.

## Recommendation

Finish the structured WebKit result bridge for click/fill and keep MCP as a thin CLI delegate. Do not add JSON-RPC `details` yet.

## Findings

- Prior taxonomy used human message substring matching as the primary route.
- R2 should keep legacy message classification only as a fallback.
- Click/fill actionability failures should flow through structured WebKit results like `{ ok: false, code, message }`.
- Strict-native work should record evidence, not claim success unless the probe returns `method: "native"`, `nativeVerified: true`, and `fallbackUsed: false`.

## Implementation response

- Added `AgentSafariError.actionabilityFailed(code:message:)`.
- Added `throwActionabilityFailureIfPresent(_:)` to bridge structured WebKit actionability results into typed Swift errors.
- Updated click target preparation and fill actionability validation to return structured failures.
- Added `AgentSafariError.nativeClickUnverified` so the strict `--native --no-fallback` miss no longer depends on message classification.
- Added `scripts/smoke_real_world.py --strict-native-probe` to record `native-verified` or `environment-gated` evidence without weakening the strict hard gate.
- Kept legacy actionability message classification as the fallback for untyped errors.
- Preserved failed CLI payload `error.code` through the thin MCP wrapper exception path.

## Codex QA follow-up

Initial `cx` QA failed the branch on two issues: typed Swift errors bypassed the legacy fallback classifier for untyped `AgentSafariError` cases, and the MCP wrapper dropped failed payload `error.code` values from exceptions. Both were fixed before merge review.

Final `cx` QA re-review passed with no merge-blocking findings after targeted probes for the legacy fallback branch, MCP error-code preservation, and strict-native evidence claims.

## Verification evidence

- `swift test`
- `python3 Tests/test_agentic_refs_contract.py`
- `python3 Tests/test_mcp_contract.py`
- `python3 Tests/test_smoke_real_world.py`
- `bash scripts/smoke_cli.sh`
- `python3 scripts/smoke_real_world.py --skip-build --out-dir .tmp/agent-safari-5-scenarios-r2-fixed`
- `python3 scripts/smoke_real_world.py --skip-build --strict-native-probe --out-dir .tmp/agent-safari-strict-native-probe-r2-fixed`
- `AGENT_SAFARI_STRICT_NATIVE=1 python3 scripts/smoke_real_world.py --skip-build --out-dir .tmp/agent-safari-strict-hard-gate-r2-fixed`

## Overclaim guard

Current local strict-native probe result is `environment-gated` with `error.code: native_click_unverified`; this is not a strict native success claim.
