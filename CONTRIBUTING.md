# Contributing

Issues are welcome: bugs, wrong figures, ideas. A screenshot of the popover and your macOS version help most.

Pull requests are welcome too. Keep them small, one change each, and run `swift build`, `swiftlint lint --strict` and the tests before you open one (the README has the test command). A change in behaviour comes with a test for it.

The app keeps a few rules, and a change that needs to break one will not be merged:

- No network calls of any kind. No analytics, no update check, no price fetch.
- Plan figures come only from Claude Code's documented status line feed. No Keychain, no token, no private endpoint.
- Transcripts are read for the fields the privacy page names and nothing else; `memory/` and `tool-results/` are never opened.
- `settings.json` is touched only on a click, and only its `statusLine` key changes.
- Cost is labelled list price equivalent, never spent.
- No em dash, en dash, middle dot or pipe in the UI or the docs.

## Releasing

Run `scripts/preflight.sh` first: it runs every step CI runs, the tests in three time zones, and the checks earlier releases missed. Set the version's heading in `CHANGELOG.md` from "unreleased" to the release date, then push the tag `v<version>`. The tag runs `.github/workflows/release.yml` on GitHub's machines: it runs the tests, builds the zip, its SHA-256 and the SBOM with `scripts/build-app.sh`, records a signed build provenance for the zip (`gh attestation verify build/tokenpanda-<version>.zip --repo tokenpandadev/tokenpanda-app` checks it), and opens a draft release with those four files and the version's CHANGELOG section as its notes. It stops when that section is missing, empty or still says "unreleased". A re-run replaces the draft's files; a release already published is left alone.

Try the zip from the draft on a clean Mac, then publish the draft by hand. The cask's `sha256` is the one in the draft's `tokenpanda-<version>.zip.sha256`, the zip CI built, never one from a local build. After each audit, `python3 -I scripts/audit-page.py <audit folders>` rebuilds `docs/audit.html`.
