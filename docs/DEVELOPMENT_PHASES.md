# Agent Safari Phased Development Plan

> Build Agent Safari through evidence-backed phases. Each phase must preserve the product vision in `docs/PRODUCT_VISION.md`, the product contract in `docs/PRODUCT_SPEC.md`, and the observe → act → wait → verify loop in `docs/AGENT_LOOP.md`.

## Operating Model

Every phase follows the same loop:

1. **Plan** — write or update the phase section and acceptance criteria before coding.
2. **Implement** — keep changes small and commit-worthy.
3. **Verify** — run the phase gates and capture real output/artifacts.
4. **Vision review** — ask a Claude Code session using `docs/PRODUCT_VISION.md` as its reviewer persona to check alignment and overreach.
5. **Document** — update specs, usage docs, roadmap, release checklist, and wiki evidence.
6. **Commit** — commit code and docs together when they prove the same milestone.

## Phase Status Legend

- **Done** — implemented, tested, documented, and released or merged.
- **Active** — current workstream.
- **Planned** — accepted direction but not started.
- **Gated** — do not implement until a preceding phase proves the needed foundation.
- **Research** — exploratory only; no product claims until verified.

## Vision Priority Crosswalk

- `docs/PRODUCT_VISION.md` Priority 1, strict native click/actionability hardening → Phase 2.
- `docs/PRODUCT_VISION.md` Priority 2, capture and inspection metadata → Phase 3.
- `docs/PRODUCT_VISION.md` Priority 3, session/browser model after single-WebView stability → Phase 5.
- Network export beyond the current fetch/XHR instrumentation → Phase 4.
- Packaging, installation, public demo, and distribution polish → Phase 6.

## Phase 0 — Public Release Hygiene

Status: Done through `v0.0.6`.

Goal: Make the repository safe and useful as a public open-source project.

Completed capabilities:

- MIT license;
- clean public repository baseline;
- public GitHub description, topics, and release artifacts;
- CI on macOS;
- public-release audit;
- release checklist;
- Homebrew/GitHub release packaging path;
- npm wrapper prepared but unpublished.

Acceptance criteria:

- `scripts/public_release_audit.py` passes.
- Release assets can be downloaded and checksum-verified.
- Docs do not leak local-only paths, secrets, or unsupported claims.

## Phase 1 — Deterministic Smoke And Agent Loop Baseline

Status: Done through `v0.0.6`.

Goal: Prove that a real WebKit daemon can support repeatable observe → act → wait → verify workflows.

Completed capabilities:

- CLI smoke;
- MCP wrapper smoke;
- five-scenario real-world smoke;
- bounded smoke artifacts;
- screenshot evidence;
- network metadata scenario;
- native input smoke scenario;
- release gate documentation.

Acceptance criteria:

- `bash scripts/smoke_cli.sh` exits 0.
- `python3 scripts/smoke_mcp_wrapper.py` exits 0 where applicable.
- `python3 scripts/smoke_real_world.py` reports `5/5 PASS` from a logged-in GUI session.
- Smoke report paths are recorded in release/wiki notes.

## Phase 2 — Native Input And Agentic Refs Trust

Status: Active. First checkpoints completed in `v0.0.6`; remaining work should focus on strict native click/actionability.

Goal: Make element selection and browser actions reliable enough that agents can trust snapshot refs and understand failures.

Completed checkpoints:

- snapshot schema v2 and stable DOM-order indexing;
- agentic refs contract tests;
- actionability validation for hidden/disabled/off-viewport targets;
- input/textarea/contenteditable key-path coverage;
- `Enter`, `Backspace`, and select-all shortcut coverage;
- real-world smoke scenario 5.

Remaining work:

1. Harden `click --native` focus transitions.
2. Improve coordinate conversion and viewport scrolling before click.
3. Add stricter occlusion diagnostics.
4. Refine stale/hidden/disabled/out-of-bounds/hittable errors.
5. Keep MCP parity for any new input/actionability result fields.

Acceptance criteria:

- Contract tests cover new ref/actionability semantics.
- Real-world smoke includes at least one target that requires scroll/focus handling.
- Strict native-only mode either passes in a suitable local environment or reports a documented environment-sensitive failure.
- Default fallback behavior always records method, native verification, fallback use, and native error when applicable.

Recommended gates:

```sh
swift test
python3 Tests/test_agentic_refs_contract.py
python3 Tests/test_input_keypath_contract.py
python3 Tests/test_browser_chrome_contract.py
bash scripts/smoke_cli.sh
python3 scripts/smoke_real_world.py
```

## Phase 3 — Capture And Inspection Metadata

Status: Planned.

Goal: Give agents richer page state and screenshot context without overclaiming browser-level control.

Work items:

1. Add screenshot metadata: viewport size, page size, scale, tile count, output path, and warnings.
2. Improve full-page stitching for tall pages, fixed headers, lazy-loaded content, and high-DPI scaling.
3. Extend wait predicates for URL, title, and visibility.
4. Improve `observe` with page load state, URL/title, active element, pending network count, and selected text if useful.
5. Add docs and smoke coverage for metadata fields.

Acceptance criteria:

- Screenshot commands return structured metadata in CLI and MCP responses.
- Metadata fields are contract-tested.
- Full-page smoke still proves the captured image is taller than the viewport image.
- Waits remain timeout-bounded and return structured errors.

## Phase 4 — Network Capture Hardening

Status: Planned / partly implemented for fetch/XHR instrumentation.

Goal: Improve network evidence while keeping scope honest.

Work items:

1. Refine fetch/XHR metadata and body-preview controls.
2. Document unsupported capture classes: parser resources, WebSockets, service workers, downloads, and full HAR completeness.
3. Keep redaction defaults conservative.
4. Treat proxy/HAR capture as a separate opt-in research spike.

Acceptance criteria:

- Export schema is documented.
- Body preview limits are tested.
- Docs clearly say this is JavaScript fetch/XHR instrumentation, not full browser capture.

## Phase 5 — Session, Tab, And Profile Model

Status: Gated.

Goal: Move beyond placeholder tab/session/profile commands only after single-WebView semantics are stable.

Work items:

1. Define what a tab/window/session/profile means in a WKWebView daemon.
2. Decide artifact isolation rules.
3. Decide cookie/cache/storage lifecycle.
4. Define MCP multi-session behavior.
5. Implement only the smallest model that supports reliable agent workflows.

Acceptance criteria:

- A written design note exists before implementation.
- Existing single-WebView commands remain deterministic.
- New IDs and lifecycle commands are contract-tested.
- State cleanup is documented and smoke-tested.

## Phase 6 — Productization And Distribution

Status: Planned.

Goal: Make installation, MCP registration, releases, and demos reliable for external users.

Work items:

1. Keep Homebrew tap release flow verified.
2. Decide if/when npm package should be published.
3. Keep `agent-safari-mcp-setup` consent-first and client-aware.
4. Maintain public README demo clarity.
5. Add a minimal public demo that communicates the browser-control substrate without overclaiming CDP parity.

Acceptance criteria:

- Release checklist remains accurate.
- Install docs match actual artifacts.
- Public demo exercises observe → act → wait → verify.

## Phase Review Checklist

Before closing any phase:

- [ ] Does the work strengthen eyes, hands, evidence, or failure explanation?
- [ ] Are unsupported CDP/HAR/passkey/session claims avoided?
- [ ] Are CLI and MCP semantics aligned?
- [ ] Are contract tests updated?
- [ ] Is GUI smoke updated if the behavior touches WebKit runtime?
- [ ] Did a Claude Code product-vision reviewer inspect the change?
- [ ] Are docs and wiki evidence updated?
