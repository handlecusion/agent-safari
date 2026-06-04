# Agent Safari Product Vision

> Canonical source: LLM Wiki page `wiki/projects/agent-safari-product-vision.md`.
> This repository copy exists so Claude Code, reviewers, and contributors can use the product vision while working inside the codebase.

## Concise Definition

`agent-safari` is the local-first macOS WebKit control substrate that lets AI agents see, inspect, click, type, wait, capture evidence, and explain failures in a real browser.

Short phrasing:

> AI agent가 브라우저를 사람처럼 다루게 만드는 손/눈/검증 레이어.

## Product Intent

The intent is not to build another generic browser automation library or a full Chrome DevTools Protocol clone. The intent is to give local AI agents a trustworthy native browser execution layer:

1. **Eyes** — page text, HTML, DOM snapshots, element refs, screenshots, and inspection metadata.
2. **Hands** — click, fill, key, type, viewport, wait, and native input paths.
3. **Evidence** — bounded smoke artifacts, screenshots, network metadata, release gates, and reproducible reports.
4. **Failure explanations** — explicit errors for hidden, disabled, stale, off-viewport, occluded, or otherwise non-actionable targets.

The product should make browser work verifiable enough for code review, QA, release checks, and agentic task execution, not just interactive demos.

## Strategic Role

`agent-safari` sits under Hermes, LLM Wiki, code-review harnesses, and autonomous coding agents as browser-control infrastructure.

It supports workflows where an agent needs to:

- verify a web UI after a code change;
- gather browser evidence for a review or release;
- inspect pages without relying only on text scraping;
- interact with form fields, buttons, and dynamic DOM state;
- produce clear artifacts when a browser task fails;
- run from a local-first, privacy-preserving macOS environment.

This makes `agent-safari` a substrate for agent operations, not a standalone consumer browser product.

## Product Principles

### 1. Native WebKit first

Use a real macOS AppKit/WKWebView runtime controlled by a daemon. Keep the browser lifecycle outside the LLM process and outside host apps like `cmux`.

### 2. One control protocol

The Python MCP wrapper should stay thin and delegate to the CLI. The Swift CLI/socket daemon remains the canonical browser-control implementation.

### 3. Agentic refs must be trustworthy

DOM snapshot refs such as `@e1` are core product surface. They need stable ordering, useful metadata, actionability checks, and clear error semantics.

A ref is only valuable if an agent can safely decide: “this is the element I should click/type into” and later know why it succeeded or failed.

### 4. Input reliability beats feature breadth

Before adding large browser capabilities, make click/type/key/fill paths boringly reliable for common agent tasks: inputs, textareas, contenteditable fields, buttons, shortcuts, focus transitions, and viewport interactions.

### 5. Evidence over claims

Every release should be backed by real gates: Swift tests, contract tests, smoke tests, public-release audit, artifact verification, and clear smoke reports. Avoid claiming capabilities that are not exercised.

### 6. Honest scope boundaries

Do not overclaim CDP/HAR-equivalent capability. Browser-level network interception, WebSocket frames, downloads, service workers, true multi-target sessions, and profile isolation are separate future tracks.

Passkey/WebAuthn automation remains out of scope unless explicitly reopened.

## Current Product Shape After v0.0.6

As of release `v0.0.6`, the project has crossed from “public demo/control surface” into “minimum credible agent-control substrate.”

Important completed checkpoints:

- public GitHub release hygiene;
- MIT license, CI, release audit, and clean public history;
- CLI and MCP control surfaces;
- navigation, text/HTML extraction, JS evaluation, screenshots, waits, status/observe;
- DOM snapshot refs with schema/actionability hardening;
- native typing/key-path coverage for input, textarea, contenteditable, `Enter`, `Backspace`, and `Meta+A`/`Ctrl+A` style shortcuts;
- fetch/XHR network metadata capture and redacted export;
- real-world smoke reports and release artifact verification.

## Near-term Direction

The next work should keep the product focused on browser-control trust rather than broadening prematurely.

### Priority 1 — Strict native click and actionability hardening

Improve:

- native click focus transitions;
- coordinate conversion;
- viewport scrolling before click;
- occlusion diagnostics;
- native-only failure reports;
- stale/hidden/disabled/out-of-bounds/hittable-coordinate errors.

This is the most aligned next step because the core promise is reliable agent action in a real browser.

### Priority 2 — Capture and inspection metadata

Improve screenshots, full-page capture, wait predicates, and `observe` so agents get better state awareness:

- viewport/page size;
- scale and tile count;
- screenshot warnings;
- page load state;
- URL/title visibility predicates;
- active element;
- pending network count;
- selected text where useful.

### Priority 3 — Session/browser model after modeled WebView stability

Only after the single-daemon modeled WebView semantics stay stable, evolve the tab/session/profile surface toward stronger isolation.

Questions to resolve:

- What does a tab mean in a WKWebView daemon?
- How are cookies/cache/storage scoped?
- What should MCP multi-session behavior guarantee?
- How are artifacts isolated per run?

## Deliberate Non-goals For Now

- Full Chrome DevTools Protocol replacement.
- HAR-grade proxy capture by default.
- True multi-tab/profile isolation before modeled daemon command semantics are stable.
- WebAuthn/passkey automation.
- Browser extension dependency.
- Cloud-hosted multi-user browser service.

## Success Criteria

`agent-safari` is moving in the right direction when:

1. An agent can inspect a page, select a ref, act on it, and get deterministic feedback.
2. Common form and keyboard workflows pass repeatable local smoke tests.
3. Failures are diagnosable from structured errors and artifacts.
4. Releases are backed by CI, contract tests, smoke reports, and artifact verification.
5. The MCP tool surface remains thin, predictable, and aligned with CLI behavior.
6. The project does not blur into unsupported CDP/HAR claims.

## Recommended Positioning

Public-facing positioning:

> Agentic Safari/WebKit browser controlled from a CLI and MCP wrapper.

Longer product positioning:

> A local-first macOS WebKit automation daemon for AI agents that need reliable browser inspection, input, screenshots, waits, network metadata, and evidence-backed release/QA workflows.

Internal decision filter:

> Does this make an AI agent more reliable at seeing, acting, verifying, or explaining failure in a real browser?

If yes, it likely belongs in `agent-safari`. If it mainly adds breadth without improving agent reliability or evidence, it should wait.
