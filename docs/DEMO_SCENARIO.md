# Agent Safari real demo scenario

This demo GIF is generated from a live Agent Safari run against a local WebKit page.

Scenario:

1. Start the native Agent Safari daemon in a macOS GUI session.
2. Open a local release-candidate QA page in the controlled WKWebView.
3. Call `snapshot` and use the resulting browser state as agent-visible evidence.
4. Fill the issue-summary input through the Agent Safari CLI.
5. Start fetch/XHR network capture.
6. Click the audit button, causing the page to run both `fetch` and `XMLHttpRequest` calls.
7. Verify the final rendered state, export network evidence, and capture the frames used for the GIF.

Generated asset:

- `docs/assets/agent-safari-real-demo.gif`

The scenario highlights the practical Agent Safari value proposition: observe -> act -> verify in a real local Safari/WebKit browser, not a synthetic test-only environment.
