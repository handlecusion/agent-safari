# WKWebView full-page screenshot spike

Date: 2026-05-21
Scope: investigation only. This spike intentionally does not modify `Sources/AgentSafari/main.swift` or package production targets.

## Current state

`Sources/AgentSafari/main.swift` currently captures only the visible viewport:

```swift
let configuration = WKSnapshotConfiguration()
configuration.rect = webView.bounds
let image = try await webView.takeSnapshot(configuration: configuration)
```

That is safe for viewport screenshots, but it cannot guarantee full-page output because `webView.bounds` is the current 1280x720 view rectangle.

## Recommended API / strategy

Recommended production behavior:

1. Keep the existing `screenshot <path>` command as viewport-only and backwards compatible.
2. Add a full-page option on the same screenshot command:

```sh
agent-safari screenshot --full-page <path>
```

3. Internally parse it to the same RPC method with an additional parameter:

```json
{ "method": "screenshot", "params": { "path": "/tmp/page.png", "fullPage": "true" } }
```

4. In the daemon, add a separate `fullPageScreenshot(path:)` helper instead of complicating the existing viewport path.
5. Use a two-tier capture strategy:
   - Fast path: measure page dimensions with JavaScript and try one `WKSnapshotConfiguration.rect = CGRect(x: 0, y: 0, width: fullWidth, height: fullHeight)` when the pixel area is under a conservative budget.
   - Fallback path: for large pages, scroll through the document with JavaScript, capture viewport-sized tiles with `WKSnapshotConfiguration.rect = webView.bounds` or a clipped viewport tile rect, and stitch those tiles into one PNG.

Why this path is safest:

- It preserves current command behavior and avoids regressions for viewport screenshots.
- It avoids resizing the live `WKWebView` as the default. Resizing can change CSS media queries, responsive layout, sticky positioning, and viewport-dependent JavaScript.
- It gates large single snapshots behind a pixel budget to reduce blank images, WebKit failures, excessive memory, or oversized PNG encoding failures.
- It gives a deterministic fallback for long pages.

## Page measurement

Use JavaScript measurement instead of relying on AppKit-only view bounds:

```js
(() => {
  const de = document.documentElement;
  const b = document.body;
  const width = Math.max(
    de ? de.scrollWidth : 0,
    de ? de.offsetWidth : 0,
    de ? de.clientWidth : 0,
    b ? b.scrollWidth : 0,
    b ? b.offsetWidth : 0,
    b ? b.clientWidth : 0,
    window.innerWidth || 0
  );
  const height = Math.max(
    de ? de.scrollHeight : 0,
    de ? de.offsetHeight : 0,
    de ? de.clientHeight : 0,
    b ? b.scrollHeight : 0,
    b ? b.offsetHeight : 0,
    b ? b.clientHeight : 0,
    window.innerHeight || 0
  );
  return { width, height };
})()
```

## Important macOS finding

A standalone type-check found that macOS `WKWebView` does not expose the iOS-style `scrollView` property. The fallback tiling path should therefore scroll with JavaScript (`window.scrollTo(...)`) rather than `webView.scrollView` APIs.

This is captured in `docs/spikes/FullPageScreenshotSpike.swift`.

## Risks and mitigations

1. Large snapshot memory pressure
   - Risk: a full-page bitmap can be very large. Example: 1280x30000 at 2x scale is about 307 MB raw RGBA before PNG compression.
   - Mitigation: use `maxSingleSnapshotPixels`; tile and stitch for large pages; reject or cap extreme dimensions with a clear error.

2. Fixed and sticky elements in tiled fallback
   - Risk: scrolling and stitching can duplicate fixed headers, cookie banners, chat widgets, and sticky nav bars.
   - Mitigation: prefer single-rect snapshot for moderate pages; document the limitation; optionally add a future flag to hide fixed elements during tiled capture only if users request it.

3. Lazy-loaded content
   - Risk: tiled scrolling may trigger lazy loading and layout shifts.
   - Mitigation: after navigation, optionally pre-scroll once or wait briefly after each tile; record actual `window.scrollY` after each scroll and stitch using the actual value.

4. Responsive layout changes
   - Risk: resizing the `WKWebView` to content size can change page layout.
   - Mitigation: do not resize in the initial implementation; keep the visible viewport width stable.

5. Horizontal overflow
   - Risk: pages wider than the viewport may be cropped in a vertical-only tiled fallback.
   - Mitigation: v1 can capture the viewport width and report measured full width in metadata; v2 can add x/y grid tiling if horizontal overflow is important.

6. WebKit API behavior across macOS versions
   - Risk: `WKSnapshotConfiguration.rect` behavior for very tall rects can vary or fail.
   - Mitigation: keep the fast path conservative, verify on the supported package platform `.macOS(.v14)`, and fall back to tile capture.

7. Main-thread requirement
   - Risk: AppKit/WebKit APIs must run on the main actor.
   - Mitigation: keep screenshot helpers `@MainActor`, matching the existing `BrowserController` design.

## Command surface proposal

Preferred:

```sh
agent-safari screenshot <path>
agent-safari screenshot --full-page <path>
```

Alternative if parser simplicity is preferred:

```sh
agent-safari screenshot <path>
agent-safari screenshot-full <path>
```

Recommendation: use `screenshot --full-page <path>` because it keeps screenshot behavior under one command and maps cleanly to future options such as `--viewport`, `--format`, or `--quality`.

## Exact implementation steps

Do these in a normal production change after this spike is accepted:

1. Add CLI parse support in `Sources/AgentSafariCore/CommandRequest.swift`:
   - Existing: `screenshot <path>` -> `{ method: "screenshot", params: ["path": path] }`
   - New: `screenshot --full-page <path>` -> `{ method: "screenshot", params: ["path": path, "fullPage": "true"] }`
   - Keep `screenshot <path>` unchanged.

2. Add or update core tests in `Tests/AgentSafariCoreTests/CommandRequestTests.swift`:
   - `screenshot /tmp/a.png` remains viewport-only.
   - `screenshot --full-page /tmp/a.png` includes `fullPage = true`.
   - Missing path after `--full-page` fails with `missingArgument("path")`.

3. In `Sources/AgentSafari/main.swift`, split the screenshot implementation:
   - Keep `screenshot(path:)` as the current viewport code.
   - Add `fullPageScreenshot(path:)` or `screenshot(path:fullPage:)` that delegates based on the parsed flag.
   - In `handle(_:browser:)`, read `params["fullPage"] == "true"`.

4. Add helper methods inside or near `BrowserController`:
   - `measurePageSize() async throws -> CGSize`
   - `takeSingleFullRectSnapshot(pageSize:) async throws -> NSImage`
   - `takeTiledFullPageSnapshot(pageSize:) async throws -> NSImage`
   - `writePNG(_ image:path:) throws`

5. Use these conservative defaults:
   - `maxSingleSnapshotPixels`: start at 16,000,000 CSS pixels or lower if memory issues appear.
   - `maxTileHeight`: viewport height; do not exceed 4096 CSS pixels initially.
   - Per-scroll settle delay: 100-250 ms.
   - Extreme page cap: fail clearly above a configured raw pixel budget.

6. Add metadata to successful RPC responses:
   - `path`
   - `fullPage`: `true` or `false`
   - `width`
   - `height`
   - `strategy`: `viewport`, `single-rect`, or `tiled-scroll`

7. Update usage text:

```text
agent-safari screenshot <path> [--socket /tmp/agent-safari.sock]
agent-safari screenshot --full-page <path> [--socket /tmp/agent-safari.sock]
```

8. Manually verify with a running daemon before merging.

## Test plan

Automated tests:

1. CLI parser tests for `screenshot`, `screenshot --full-page`, and missing full-page path.
2. Unit test page-size parsing if the measurement script is factored into testable code.

Manual integration tests:

1. Short page:

```sh
agent-safari daemon --socket /tmp/agent-safari.sock
agent-safari navigate https://example.com --socket /tmp/agent-safari.sock
agent-safari screenshot /tmp/example-view.png --socket /tmp/agent-safari.sock
agent-safari screenshot --full-page /tmp/example-full.png --socket /tmp/agent-safari.sock
```

Expected: viewport and full-page images are both valid PNGs and roughly the same height for this short page.

2. Long static page:
   - Use a local HTML fixture with height > 5000 px and colored bands every 1000 px.
   - Expected: full-page PNG height matches measured document height and includes all bands.

3. Fixed header page:
   - Use a local fixture with `position: fixed` header.
   - Expected: document whether fallback duplicates the fixed header; single-rect path should be preferred when possible.

4. Lazy-load page:
   - Use a fixture that appends content on scroll.
   - Expected: tiled strategy waits long enough and reports actual measured height/strategy.

5. Very tall page:
   - Use a fixture around 30,000 px high.
   - Expected: single-rect path is skipped; tiled path succeeds or fails with a clear configured-limit error.

6. Retina output check:
   - Verify PNG dimensions and content on a Retina display; make sure CGContext scale/orientation is correct.

## Spike artifact

Created `docs/spikes/FullPageScreenshotSpike.swift` with a standalone `@MainActor` renderer sketch. It is not part of `Package.swift` and does not affect production builds.

Verification performed:

```sh
swiftc -typecheck docs/spikes/FullPageScreenshotSpike.swift
```

Result: type-check passed after replacing the invalid macOS `webView.scrollView` approach with JavaScript scrolling.

## Recommendation

Implement `screenshot --full-page <path>` using the two-tier strategy above. Start with conservative limits and explicit response metadata. Keep viewport screenshot unchanged. Do not resize the live `WKWebView` in v1; use JavaScript measurement plus single-rect snapshot when safe, with JavaScript-scroll tiling as the fallback.
