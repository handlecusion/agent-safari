# agent-safari roadmap

This roadmap tracks post-passkey work for the native Safari/WebKit automation daemon, CLI, and MCP wrapper.

Passkey/WebAuthn support is explicitly out of scope for this roadmap. Do not add passkey/WebAuthn automation back into this track unless a future roadmap replaces this document.

## P0: reliability and parity

- Native input reliability
  - Replace or augment synthetic DOM key/click paths with native AppKit/Quartz input where needed.
  - Preserve snapshot `@e` ref workflows while making typing, focus, and activation closer to real user input.
  - Add regression coverage for common forms, keyboard shortcuts, and focus transitions.

- Wait commands
  - Extend the existing CLI and MCP waits beyond document readiness, text predicates, selector presence, and fetch/XHR idle with URL/title predicates and visibility-specific checks.
  - Ensure waits have explicit timeouts and structured timeout errors.
  - Keep waits in smoke scripts to reduce timing flake.

- MCP parity
  - Keep MCP tools aligned with CLI commands when browser-control commands are added.
  - Status, wait, and network capture commands are now part of the MCP surface: `status`, `wait`, `wait_for_selector`, `wait_for_text`, `wait_for_idle`, `network_start`, `network_list`, and `network_stop`.
  - Keep wrapper smoke checks exercising both core navigation/evaluation and parity-sensitive tools.

## P1: capture hardening

- Screenshot hardening
  - Improve full-page stitching reliability for very tall pages, fixed-position elements, lazy-loaded content, and high-DPI scaling.
  - Return richer screenshot metadata such as viewport size, page size, scale, tile count, and warnings.
  - Add fixture pages that cover fixed headers, long pages, overflow containers, and dynamic layout.

- Network capture improvements
  - Continue improving the current JavaScript fetch/XHR instrumentation while clearly documenting unsupported browser-level capture.
  - Add bounded export formats and clearer metadata/body-preview controls.
  - Investigate proxy/HAR-style capture separately with explicit trust, cleanup, and sensitive-data handling requirements.

## P2: browser/session model

- Multi-tab support
  - Model tabs/windows explicitly in daemon state and expose tab selection/listing commands.
  - Keep command behavior deterministic when multiple pages are present.

- Profile isolation
  - Support isolated browser data/profile directories where WebKit allows it.
  - Document cookie/cache/storage lifecycle and cleanup behavior.

- Session management
  - Add session identifiers for long-lived automation runs.
  - Persist or export useful run artifacts without leaking state across sessions by default.
