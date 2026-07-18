# SYNK Music — iOS

Native SwiftUI client for **SYNK Music**, mirroring the Linux (Qt6) desktop app
and the Android (Compose) app. Talks to the SYNK API at `https://api.synkmusic.xyz`.

## Requirements

- **macOS + Xcode 15+** (iOS apps can only be compiled and signed on macOS).
- [XcodeGen](https://github.com/yonwoo9/XcodeGen) — `brew install xcodegen`.
- iOS 17.0+ deployment target.

## Generating the Xcode project

The `.xcodeproj` is **not** committed — it is generated from `project.yml`:

```sh
brew install xcodegen      # once
xcodegen generate          # creates SynkMusic.xcodeproj
open SynkMusic.xcodeproj
```

Then select your device/simulator and hit **Run** (⌘R). To run on a physical
iPhone you must set a **Development Team** under *Signing & Capabilities* (a free
Apple ID works for on-device testing).

## Command-line build

```sh
xcodegen generate
xcodebuild -project SynkMusic.xcodeproj -scheme SynkMusic \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Project layout

```
SynkMusic/
  App/            SynkMusicApp (entry), RootView
  Networking/     API client, Codable models, Keychain AuthStore
  Stores/         SessionStore, LikesStore, DownloadStore, SettingsStore
  Playback/       PlayerController (AVPlayer), MiniPlayer, FullPlayer,
                  LyricsView, QueueView, ListenTracker, DominantColor
  Screens/        Home, Search, Library, Detail, Analytics, Profile,
                  Settings, Equalizer, Downloads, Auth
  Components/     Artwork, TrackRow/LikeButton/DownloadButton, TrackActionsSheet
  Design/         Theme (colors + fonts), SynkIcons (heroicons), SVGPathParser
  Fonts/          Host Grotesk (UI) + Figtree (lyrics)
  Assets.xcassets AppIcon, SynkLogo, LaunchBackground
```

## Conventions

- **No code comments** beyond short intent notes; terse style matching the other clients.
- Brand is always all-caps **SYNK** in user-facing strings.
- Colors come from `Theme` (Ink `#000`, Surface `#0e0e0e`, Muted `#b3b3b3`, …),
  matching the desktop/Android palette.
- Icons are heroicons SVG paths rendered via `SVGPathParser` → `CGPath`.

## Notes

- Background audio + lock-screen controls via `AVAudioSession(.playback)` +
  `MPRemoteCommandCenter` / `MPNowPlayingInfoCenter`.
- Stream URLs are resolved up-front before `AVPlayerItem` creation so playback
  starts reliably (same lesson as the Android fix).
- The EQ screen persists 10 bands; wiring them into an `AVAudioEngine` graph is a
  follow-up (AVPlayer doesn't expose a band EQ directly).
