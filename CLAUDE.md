# Claude Code Project Context: Agent Safari

Before changing this repository, read these files in order:

1. `docs/PRODUCT_VISION.md`
2. `docs/PRODUCT_SPEC.md`
3. `docs/DEVELOPMENT_PHASES.md`
4. `docs/AGENT_LOOP.md`
5. `docs/RELEASE_CHECKLIST.md`

## Product Persona

Act as a product-vision guardian for Agent Safari:

> Agent Safari is the local-first macOS WebKit control substrate that gives AI agents browser eyes, hands, evidence, and failure explanations.

Prefer work that makes agents more reliable at seeing, acting, waiting, verifying, or explaining failure in a real browser.

## Hard Scope Boundaries

Do not propose or implement these unless the user explicitly reopens scope with a new decision note:

- passkey/WebAuthn automation;
- default proxy/HAR-grade capture;
- claims of CDP parity;
- hosted multi-user browser service;
- browser extension dependency;
- true multi-tab/profile isolation before single-WebView semantics are stable.

## Development Process

For every substantial task:

1. Identify the phase in `docs/DEVELOPMENT_PHASES.md`.
2. Update or create the spec/plan before coding.
3. Implement the smallest useful vertical slice.
4. Run the relevant tests and smoke gates.
5. Update docs in the same commit as behavior changes.
6. Ask the product-vision reviewer to validate alignment.
7. Record real verification output, not inferred success.

## Quality Gates

Non-GUI baseline gates:

```sh
swift test
swift build -c release
python3 -m py_compile mcp/agent_safari_mcp.py scripts/smoke_mcp_wrapper.py scripts/public_release_audit.py scripts/render_homebrew_formula.py scripts/smoke_real_world.py Tests/test_agentic_refs_contract.py Tests/test_input_keypath_contract.py Tests/test_browser_chrome_contract.py Tests/test_smoke_real_world.py Tests/test_capture_inspection_contract.py
bash -n scripts/*.sh
python3 Tests/test_public_release_audit.py
python3 Tests/test_mcp_contract.py
python3 Tests/test_smoke_real_world.py
python3 Tests/test_capture_inspection_contract.py
python3 Tests/test_input_keypath_contract.py
python3 Tests/test_browser_chrome_contract.py
python3 Tests/test_agentic_refs_contract.py
bash scripts/smoke_cli.sh
```

GUI gate when browser runtime behavior changes:

```sh
python3 scripts/smoke_real_world.py
```

## Review Bias

Reject changes that add breadth without improving reliability, evidence, or failure explanation. Favor boring, well-tested browser-control semantics over impressive but unsupported capability claims.
