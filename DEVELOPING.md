# Developing Larkdown

Larkdown uses AppKit and `NSDocument` for native document behavior. The app target
owns windows, menus, WebKit, signing, and updates. The local Swift package at
`Packages/LarkdownCore` owns Markdown parsing, rendering, preview HTML, source
highlighting, encoding, and line endings.

Larkdown ships as a direct download only. The app is Developer ID signed,
notarized, and uses the hardened runtime. It is not sandboxed, like Ghostty.
It updates itself through Sparkle, using releases published on GitHub.

## Setup

Install Xcode and select its command-line tools:

```sh
sudo xcode-select --switch /Applications/Xcode.app
scripts/doctor.sh
```

Swift Package Manager resolves the dependencies:

- `swift-cmark` provides the cmark-gfm parser and HTML renderer.
- Sparkle 2.10.0 provides updates. Xcode embeds its framework in the app.
- highlight.js ships as a bundled resource of `LarkdownCore`.

Normal development requires no Apple Developer Program membership or release
credentials.

The deployment target is macOS 13. CI runs on macOS 15 and macOS 26; those runners
do not establish runtime compatibility with macOS 13. Before release, test on
macOS 13 separately.

## Build and test

Run commands from the repository root:

| Command | Purpose |
| --- | --- |
| `swift test --package-path Packages/LarkdownCore` | Run focused package tests. |
| `scripts/test.sh` | Run package and native app tests. |
| `scripts/test.sh --ui-tests` | Also run UI tests. |
| `scripts/build.sh` | Build Debug. |
| `CONFIGURATION=Release scripts/build.sh` | Build the direct-distribution configuration. |
| `scripts/check-distribution.sh APP` | Check a built app bundle for distribution settings. |
| `scripts/install-local.sh 0.1.0` | Build and install an ad-hoc Release app in `~/Applications`. |
| `scripts/uninstall-local.sh` | Remove the local installation. |

Run builds and tests sequentially. Tests have execution timeouts to make stalls
visible. Check the final test result, not only build success.

UI tests launch app windows and control the keyboard and mouse, so they need an
unlocked desktop session. `scripts/test.sh` skips them unless you pass
`--ui-tests`. CI skips them too.

`scripts/test.sh` builds into a temporary folder, not `.build/DerivedData`.
macOS asks before an app reads files in your Desktop, Documents, or Downloads
folder, and each ad hoc signed rebuild is a new app to macOS. If tests ran from
a checkout in one of those folders, the prompt would return after every rebuild
and wait for an answer. To build the tests elsewhere, set `DERIVED_DATA_PATH`.

After distribution changes, inspect the Release app:

```sh
CONFIGURATION=Release scripts/build.sh
scripts/check-distribution.sh .build/DerivedData/Build/Products/Release/Larkdown.app
```

The check confirms that the app has no App Sandbox entitlement, embeds and links
Sparkle, includes `ThirdPartyNotices.txt`, has an HTTPS update feed, requires
signed feeds, and stays running for 3 seconds after launch. For Developer ID builds, it also requires the
hardened runtime. Local builds are signed ad hoc and skip the hardened runtime,
because its library validation rejects the ad hoc signed Sparkle framework;
`scripts/package-release.sh` enables it for Developer ID builds.

To make a local installation the default Markdown handler, select a Markdown
file in Finder, choose **File > Get Info**, select Larkdown under **Open with**,
and choose **Change All**.

## Implementation map

- `LarkdownDocument.swift` preserves UTF-8 BOM and line-ending state and connects
  native saving and undo.
- `EditorSplitViewController.swift` debounces rendering, rejects stale results,
  and synchronizes editor scrolling to preview.
- `MarkdownEditorViewController.swift` owns `NSTextView` and highlighting.
- `MarkdownPreviewViewController.swift` owns a nonpersistent `WKWebView`,
  incremental updates, and link navigation.
- `PreviewResourceSchemeHandler.swift` serves local files to the preview through
  the `larkdown-file` scheme.
- `UpdaterController.swift` starts Sparkle when the app has a valid public key and
  an HTTPS feed. Development builds have an empty key, so **Check for Updates…**
  stays disabled. This is the only file that imports Sparkle.
- `MainMenuFactory.swift` builds native menus without storyboards.
- `MarkdownRenderer.swift` in `LarkdownCore` renders Markdown to HTML with
  cmark-gfm.
- `PreviewHTMLDocument.swift` wraps rendered HTML in the page, Content Security
  Policy, and preview script.
- `PreviewResource.swift` maps documents and local files to `larkdown-file` URLs.

Markdown source remains authoritative. Rendering must never rewrite source.
Unsupported encodings produce errors; UTF-8 is supported. YAML (`---`) and TOML
(`+++`) front matter is preserved and hidden from the preview.

## Rendering and preview security

Larkdown renders GitHub Flavored Markdown with cmark-gfm: tables, task lists,
strikethrough, autolinks, and footnotes. Like GitHub, it passes raw HTML through
and applies the `tagfilter` extension, which escapes tags such as `<script>`.
Simple HTML, such as a centered `<p align="center"><img …></p>` logo, renders.

Larkdown relies on WebKit to contain the preview rather than sanitizing HTML:

- The preview is a nonpersistent `WKWebView`.
- A nonce-based Content Security Policy allows only Larkdown's own script and
  style. Document scripts, event handlers, styles, forms, frames, and `<base>`
  elements are blocked.
- Link clicks never navigate the preview. Links to `http`, `https`, and `mailto`
  open in the default handler. Links to Markdown files open in Larkdown. Links to
  other local files are revealed in Finder. All other navigation is cancelled.

Images load as follows:

- Remote images load by default, over HTTPS or HTTP. `NSAllowsArbitraryLoadsInWebContent`
  permits HTTP in the preview only. Remote images can disclose your IP address
  to the image host.
- Local images and other local resources load through the `larkdown-file` scheme.
  The page base URL is `larkdown-file://` plus the document's folder, so relative
  paths, including `../`, resolve in WebKit. The app process reads the files, so
  macOS may ask once for access to the Desktop, Documents, or Downloads folder.

### Mac App Store (future)

A Mac App Store port needs these changes:

- App Sandbox entitlements.
- User-granted folder access for linked local images, because the sandbox blocks
  reads outside the opened file.
- A build without Sparkle.

## Local release candidates

```sh
RELEASE_NAME=0.1.0-rc.1 scripts/package-release.sh 0.1.0
```

The package script creates a universal Apple silicon/Intel app, ZIP, DMG, symbols,
and relative-path checksums under `dist/release/Larkdown-0.1.0-rc.1/`. It refuses
to replace existing output. Use a new candidate label or `OUTPUT_DIR` for another
run. It retains the archive and staging files under a unique `.build/release.*`
directory for inspection. Set `SKIP_TESTS=1` only after testing the same source.

The script resolves packages into `.build/SourcePackages` and takes Sparkle's
signing tools from that checkout.

Ad-hoc candidates have no public signing or notarization. Unless you configure
Sparkle keys, they have no enabled updater or appcast. Do not publish them as
public downloads.

## Public release setup

Public packages require:

- A Developer ID Application certificate and private key.
- Your Apple Developer team ID.
- An App Store Connect notarization API key and `notarytool` profile.
- A Sparkle Ed25519 key pair, backed up securely.

Create a notarization profile using your own credentials:

```sh
xcrun notarytool store-credentials larkdown-notary \
  --key /path/to/AuthKey.p8 --key-id YOUR_KEY_ID --issuer YOUR_ISSUER_ID
```

Resolve packages so Sparkle's tools are available. Then generate a Sparkle key in
your login Keychain and export its private seed to a secure location outside the
checkout:

```sh
xcodebuild -resolvePackageDependencies -project Larkdown.xcodeproj \
  -scheme Larkdown -clonedSourcePackagesDirPath .build/SourcePackages
.build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account larkdown
.build/SourcePackages/artifacts/sparkle/Sparkle/bin/generate_keys --account larkdown -x /secure/path/sparkle-private-key
```

Use the printed public key for `SPARKLE_PUBLIC_ED_KEY`. The package script accepts
the current 32-byte private-seed export format and checks that it matches the
public key before building. Never commit the seed or private signing credentials.
Keep the same update key across releases and keep a secure backup. The app sets
`SURequireSignedFeed` and `SUVerifyUpdateBeforeExtraction`, so Sparkle can rotate
the key only through a Developer ID signed disk image update. Larkdown publishes
ZIP updates, so if you lose the key, installed copies can't update themselves.

```sh
SIGNING_MODE=developer-id \
DEVELOPMENT_TEAM=YOUR_TEAM_ID \
NOTARIZE=1 NOTARY_PROFILE=larkdown-notary \
SPARKLE_PUBLIC_ED_KEY=YOUR_PUBLIC_KEY \
SPARKLE_PRIVATE_KEY_FILE=/secure/path/sparkle-private-key \
scripts/package-release.sh 0.1.0
```

The package script archives both architectures, exports with `developer-id` to
sign nested Sparkle services, verifies signing, notarizes and staples the app,
and then creates its ZIP. It signs, notarizes, and staples the DMG separately.
The final ZIP and appcast receive Sparkle signatures. The app rejects unsigned
feeds, so re-sign `appcast.xml` with `sign_update` after any edit. If you add
release notes links, sign those files too. Third-party licenses ship in the app
bundle.

Use increasing build numbers for every public release. The default is a UTC
second timestamp, also used by CI. If you explicitly supply a local build number,
it must exceed all previously published builds; Sparkle compares build numbers,
not only visible version labels.

The app's stable feed is the `appcast.xml` asset of GitHub's latest release.
Each feed contains the current full ZIP with a version-specific download URL.
There are no deltas or beta feed in this release. Preserve older release assets.
If you later raise the minimum macOS version, design a feed with compatible
historical items before publishing that change.

## GitHub Actions

CI runs tests, Debug and Release builds, shell syntax checks, and the distribution
check. The release workflow uses `macos-26`, validates its inputs and required
configuration, then builds signed artifacts in an ephemeral keychain. It removes
temporary private keys and the keychain in an `always()` cleanup step.

Release credentials live in a GitHub environment named `release`. Its deployment
policy allows only `v*` tags, so workflows on branches and pull requests can't
read them. A tag ruleset limits creating, moving, and deleting `v*` tags to
repository admins.

Configure these `release` environment secrets:

```text
APPLE_TEAM_ID
APPLE_NOTARIZATION_ISSUER
APPLE_NOTARIZATION_KEY_ID
APPLE_NOTARIZATION_KEY
DEVELOPER_ID_APPLICATION_CERTIFICATE_BASE64
DEVELOPER_ID_APPLICATION_CERTIFICATE_PASSWORD
MACOS_CI_KEYCHAIN_PASSWORD
SPARKLE_PRIVATE_KEY
```

Set the repository variable `SPARKLE_PUBLIC_ED_KEY` to the matching public key.
The certificate secret is a base64-encoded `.p12` containing the certificate and
private key. The Sparkle secret contains the exported base64 seed text.

Pushing a `v0.1.0` or `v0.1.0-rc.1` tag creates a **draft** GitHub release using
`RELEASE_NOTES.md` from the tagged commit. Candidate labels also
set GitHub's prerelease flag. Publishing remains a separate maintainer action.

Release candidates (`-rc.N`) check the signing pipeline. They stay drafts and do
not receive updates. Never make a candidate the latest stable release. Publishing
a stable draft activates the feed for installed clients, so test updates with two
consecutive stable releases before you announce.

Before you publish:

1. Check CI, version/build metadata, checksums, universal architectures, bundle
   identifiers, signed entitlements, and bundled licenses.
2. Install the downloaded, quarantined DMG on a clean Mac. Verify Gatekeeper,
   drag-to-Applications installation, launch, and Markdown file association.
3. On macOS 13 and a current macOS, on both Intel and Apple silicon, check
   editing, save/reopen, autosave, undo/redo/revert, Save As, and canceled or
   failed saves. Include BOM, CRLF, large documents, and linked images.
4. Check keyboard navigation, VoiceOver labels, dark/light appearance, and
   split-pane behavior at the minimum width.
5. Test a real update. Install version N, publish version N+1, and confirm that
   Sparkle offers and installs it. Check that a tampered ZIP is rejected.
6. Review release notes and the draft assets.

Build success alone does not establish signing, notarization, accessibility,
minimum-OS compatibility, or update installation behavior.

## Contribution guidelines

Prefer compiler checks and integration tests. Add focused package tests for
critical parsing, fidelity, or security behavior that those checks cannot cover.
Keep app lifecycle, UI, signing, and updater code in the app target. Do not
commit generated output from `.build/` or `dist/`, credentials, or personal task
state. See [contributor instructions](AGENTS.md) for repository conventions.

Release references:

- [Sparkle programmatic setup](https://sparkle-project.org/documentation/programmatic-setup/)
- [Publishing Sparkle updates](https://sparkle-project.org/documentation/publishing/)
