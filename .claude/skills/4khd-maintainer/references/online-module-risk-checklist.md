# Online Module Risk Checklist

Use this for 4KHDGallery, MissKon, Wallhaven, KnitGallery, or any future network-backed gallery module.

## Async State Isolation

- Capture section/query/page at request start.
- On return, write results to the captured bucket.
- Only update visible selection/detail if the captured route is still current.
- Cancel or ignore stale pagination/search tasks when clearing search or switching sections.

## Selection And Detail

- Cached initial selections must trigger detail resolution after callbacks are wired.
- Clearing selection should clear detail state.
- Detail controllers should not be rebuilt on every route change inside the same module unless required.
- Keep old image visible until the new image is ready when possible.

## HTML Parsing

- Do not slice an original Swift string using indices produced from `lowercased()` or another string instance.
- Use `NSString`/`NSRange`, regex captures, or case-insensitive `range(of:options:)` on the original string.
- Keep parser failures explicit enough for retry/error UI.
- Preserve fallbacks when target site markup is fragile.

## URL And Host Safety

- Use exact host or subdomain allowlists.
- Reject `host.contains(...)` for trust decisions.
- Normalize relative URLs against the page URL.
- Keep gallery records scoped by source site to avoid Favorites leakage.

## Verification And Streaming Media

- Open a normal WebKit verification session only after a genuine 403/challenge response; register waiters independently and remove cancelled waiters immediately.
- End the shared verification session when its last waiter cancels; never leave a challenge window or continuation alive until timeout after the owning detail closes.
- Validate the initial WebView URL, every main-frame navigation request, and every main-frame response before continuing.
- Treat playback and saving as different trust chains: AVFoundation may fetch HLS children itself, while downloaders must validate every playlist, segment, final response, and redirect.
- Reject unsupported HLS forms explicitly and clean temporary files on failure or cancellation; never silently emit a partial media file.

## Cache And Refresh

- Distinguish in-memory section cache, disk cache, and Favorites-backed sections.
- Refresh should not destroy valid visible content until replacement data is ready.
- Cache expiration should not apply to live Favorites data unless explicitly designed.

## Review Hotspots

- String range conversion and forced unwraps.
- Pagination URL construction.
- Search clear and load-more task cleanup.
- Favorite record conversion and domain validation.
- Toolbar selection state after async reloads.
