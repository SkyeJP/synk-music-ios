# SYNK Music for iOS

Native SwiftUI client for **SYNK Music**, mirroring the Linux (Qt6) desktop app
and the Android (Compose) app. Talks to the SYNK API at `https://synkmusic.co.uk/api/`.

## Requirements

- **macOS + Xcode** (iOS apps can only be compiled and signed on macOS).
  - Match Xcode to your **device's** iOS version: deploying to a device on
    **iOS 27 (e.g. iPhone 17) requires Xcode 27** (which ships the iOS 27 SDK).
    Xcode 16 tops out around iOS 18 and cannot install to an iOS 27 device.
- [XcodeGen](https://github.com/yonwoo9/XcodeGen), `brew install xcodegen`.
- Deployment target is iOS 18.0, so the app _runs on_ iOS 18+ (Liquid Glass on iOS 26+), but the SDK used
  to _build for a device_ must be ≥ that device's OS.

## Generating the Xcode project

The `.xcodeproj` is **not** committed, it is generated from `project.yml`:

```sh
brew install xcodegen      # once
xcodegen generate          # creates SynkMusic.xcodeproj
open SynkMusic.xcodeproj
```

Then select your device/simulator and hit **Run** (⌘R). To run on a physical
iPhone you must set a **Development Team** under _Signing & Capabilities_ (a free
Apple ID works for on-device testing).

## Command-line build

```sh
xcodegen generate
xcodebuild -project SynkMusic.xcodeproj -scheme SynkMusic \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO build
```

## Builds and releases (Codemagic)

`codemagic.yaml` builds an **unsigned** Release IPA on every push to `main`
(`mac_mini_m2`, latest Xcode), packages it as `Payload/SYNK.app` in
`synkmusic.ipa`, and publishes it to the GaffTech mirror with an AltStore /
SideStore source:

- Source to add in SideStore or AltStore: `https://mirrors.gafftech.co.uk/ios/source.json`
- Latest IPA (also works with Signulous): `https://mirrors.gafftech.co.uk/ios/synkmusic.ipa`

Create an environment group named `mirror` in Codemagic with:

| Variable          | Value                                                         |
| ----------------- | ------------------------------------------------------------- |
| `SSH_PRIVATE_KEY` | Private key that can log in to the mirror (mark it secure)    |
| `MIRROR_HOST`     | The mirror server's IP (the hostname is behind Cloudflare, which does not pass SSH) |
| `MIRROR_USER`     | SSH user on the mirror                                        |
| `MIRROR_PATH`     | Folder served as `/ios`, e.g. `/opt/repositories/hostedbysynk/ios` |

`MIRROR_URL` is optional and defaults to `https://mirrors.gafftech.co.uk/ios`.
Compiler errors are listed at the top of
the "Build unsigned Release" step, and the full log is the `xcodebuild.log`
artifact.

## Project layout

```
SynkMusic/
  App/            entry point, session, sign in
  Network/        API client and lenient Codable models
  Data/           Keychain auth, settings, likes, downloads
  Playback/       PlayerController (AVQueuePlayer, gapless preload), Equalizer
                  (biquads in an audio tap), DeviceTuning, Prefetcher, Playback router
  Realtime/       Connect (CdcClient, server-sent events), Listen Together (LtClient)
  UI/             Theme, icons, components, shell, player, lyrics, screens
  Design/         SVGPathParser
  Fonts/          Host Grotesk (headings) and Figtree (body), variable fonts
  Assets.xcassets AppIcon, SynkLogo, LaunchBackground
```

## Layout

The app follows the SYNK phone site (m.synkmusic.co.uk), the same as the
Android app: Home, Explore, Radio, Library and Search tabs, the account sheet
behind the avatar button, and the now playing screen with inline lyrics,
devices and queue. On iOS 26 and later it uses the system Liquid Glass tab
bar, with the mini player in the tab bar's accessory and Search as the
separate search tab; earlier versions get a frosted glass pill instead.

## Conventions

- **No code comments** beyond short intent notes; terse style matching the other clients.
- Brand is always all-caps **SYNK** in user-facing strings.
- Colors come from `Theme` (Ink `#000`, Surface `#0e0e0e`, Muted `#b3b3b3`, …),
  matching the desktop/Android palette.
- Icons are heroicons SVG paths rendered via `SVGPathParser` → `CGPath`.

## Notes

- Background audio and lock screen controls via `AVAudioSession(.playback)`,
  `MPRemoteCommandCenter` and `MPNowPlayingInfoCenter`.
- The 10-band EQ and device tuning run as RBJ biquads in an
  `MTAudioProcessingTap` on every player item, the same maths as Android's
  `EqualizerAudioProcessor`.
- The next four songs in the queue are cached whole in `Caches/audio`
  (1 GB, least recently used first out), and the next song is preloaded into
  the player for gapless playback.
- Listen Together links (`https://synkmusic.co.uk/?lt=<id>` or `synk://?lt=<id>`)
  open the session. The https form needs an Associated Domains entitlement and
  an `apple-app-site-association` file on the site, which sideloaded builds
  don't have, so share links open in the browser there.
