# Short-link investigation

## Evidence from this report

The supplied log contains keyboard layout and simulator haptics warnings; it does not contain an API response or a link-resolution error. These messages alone do not establish why opening the link fails.

The screenshot appears to show `2Dhdl8`, but lowercase l and uppercase I are ambiguous. The exact value has been requested from the user. Two read-only, unauthenticated GET requests to the configured `info_by_links` endpoint with the visually transcribed code and `packageName=com.clipo.video` produced:

1. HTTP 502 with plain error content.
2. HTTP 200 with `{"code":0,"data":null,"msg":""}`.

These observations do not establish the result for the user's authenticated session or confirmed code. No account was created, credentials read, or real user session used for these checks. Do not infer that the user's code is invalid from these observations alone.

## Client fixes

- A null-data resolution response now explains that no content was returned instead of reporting an unreadable response. Other endpoints retain their existing missing-data behavior.
- Link-resolution errors now appear in an app-styled modal. Previously they were displayed below the composer and could fall outside the visible viewport.
- Debug API logs record endpoint path, HTTP status, business code and data presence. They omit tokens, query values, passwords, user IDs and response bodies.
- Authentication retry still happens at most once and preserves the resolution-specific missing-data message.

No changes were made to short-code case, bundle identity, payment or quota logic. Existing headers, request parameters and strict response decoding remain in place pending an actual response for the confirmed short code.

## Confirmed code follow-up

The user confirmed `2DhdI8` (uppercase I). Read-only, unauthenticated requests for this exact code returned HTTP 200, business code 0, a channel landing page and three child items. The list includes `length: "50"` and `length: "0"`, while `DiskItem` previously decoded `length` as a JSON number only. This is a concrete response/model mismatch that prevents decoding the whole channel page.

`DiskItem` now accepts JSON numbers or numeric strings for duration and file size, while preserving null/missing fields as nil. Other fields remain strictly decoded. Invalid or non-finite numeric values still fail explicitly. The repair applies to root links and nested channel lists through their shared model.

Static source and diff inspection and read-only endpoint diagnostics only; no build, tests, simulator or playback validation. These unauthenticated responses do not verify the user's authenticated session or end-to-end playback. The screenshot also contained an older header/logo no longer present in the workspace source.
