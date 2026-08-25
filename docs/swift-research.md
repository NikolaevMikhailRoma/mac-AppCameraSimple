# Swift/Xcode research (2026-08-25)

Research pass done before starting the Swift branch. No code changes yet.

## Context

Swift will live on its own branch (not `main`), a future native macOS
reimplementation of the camera app, developed mostly from the terminal but
still requiring Xcode for building.

## Findings

### 1. Local Claude Code tooling
- **Skills**: only `python-env` is installed globally. No Swift/Xcode/macOS
  skill exists, and there's no project-local `.claude/` directory at all yet.
- **Plugins**: one marketplace configured (`claude-plugins-official`,
  github: anthropics/claude-plugins-official). Already installed and
  enabled: **`swift-lsp`** — SourceKit-LSP integration for `.swift` code
  intelligence (relies on the Swift toolchain already on this machine).
  Other marketplace plugins mention iOS/mobile in passing (`apollo-skills`,
  `expo`, `mapbox`, `sumup`) but none are macOS/Xcode build-focused — nothing
  to install there.
- **Custom agents / hooks**: none defined, locally or per-project, related to
  Swift/Xcode/build automation.
- **Toolchain already present and working**: full Xcode 16.4 (Build 16F6) at
  `/Applications/Xcode.app`, `swift --version` → Swift 6.1.2
  (arm64-apple-macosx15.0), `xcrun` v70. Not just Command Line Tools — the
  full IDE is installed and selected.
- **Repo state**: confirmed no `.xcodeproj`/`.xcworkspace`/`Package.swift`
  anywhere in `camera_app` — a Swift project would start from zero.

### 2. Terminal-first Xcode/Swift workflow in 2026
- **Swift Package Manager (SwiftPM)** is the standard terminal-native way to
  build Swift code (`swift build`, `swift run`) and works without opening
  Xcode's GUI; Xcode itself isn't required to install/use the toolchain, but
  some SwiftPM functionality is limited without Xcode present (not an issue
  here — Xcode 16.4 is installed).
  ([oneuptime.com](https://oneuptime.com/blog/post/2026-02-02-swift-package-manager/view), [swift.org](https://www.swift.org/install/macos/package_installer/))
- A plain SwiftPM **executable target can be turned into a real `.app` bundle**
  for macOS (icon, Info.plist, bundle structure) without ever creating an
  `.xcodeproj` — documented community pattern.
  ([theswiftdev.com](https://theswiftdev.com/how-to-build-macos-apps-using-only-the-swift-package-manager/), [forums.swift.org](https://forums.swift.org/t/building-an-app-from-a-swift-package-manager-executable-for-macos/64409))
- **XcodeGen** (generates `.xcodeproj` from a YAML/JSON spec, so the project
  file itself never has to live in git) is still actively maintained in 2026,
  release cadence has slowed but v2.46.0 shipped ~1 month ago. Still requires
  Xcode/Apple SDKs to be installed. **Tuist** is the more actively-developed
  alternative for the same job (project generation + modularization).
  ([xcodegen.com](https://xcodegen.com/is-xcodegen-still-actively-maintained/))
- **xtool** is a newer (as of ~2025/2026) cross-platform buildchain that can
  build/sign/run a minimal Swift Package as an app in well under a second,
  contrasted with the notoriously slow `xcodebuild` CLI — worth a closer look
  if raw `xcodebuild` iteration speed becomes painful.
  ([medium.com/@dimillian](https://dimillian.medium.com/build-an-ios-app-faster-than-ever-with-xtool-d6dd7780c5f7))
- Code signing for personal/local runs (no App Store) is handled via ad-hoc
  or "Sign to Run Locally" / personal Development Team signing —
  `xcodebuild` examples for this exist but weren't pinned down to a specific
  macOS+SwiftPM recipe yet; this needs a follow-up, narrower search once we
  pick an approach (raw SwiftPM+manual bundle vs. XcodeGen vs. xtool).

### 3. Claude Code ecosystem
- No official or community Claude Code plugin found beyond `swift-lsp` (code
  intelligence only, not build/run automation). No hooks or agents exist for
  driving `xcodebuild`/`swift build` — if we want build-on-save or a
  "build+run" custom command, we'd write our own hook/agent, there's nothing
  off-the-shelf to adopt.

## Candidate approaches for the Swift branch

Not decided yet — three viable options, roughly "closest to what we already
do in Python" to "most Xcode-native":

1. **Pure SwiftPM executable → hand-rolled `.app` bundle.** Keeps everything
   terminal-driven (`swift build`, `swift run`), matches the Python branch's
   spirit, but AVFoundation camera capture + a real app icon/Info.plist need
   manual bundle assembly — more plumbing, well documented though.
2. **XcodeGen-managed `.xcodeproj`, driven by `xcodebuild` from the
   terminal.** `.xcodeproj` is generated from a checked-in YAML spec (never
   hand-edited or committed as XML), still buildable/runnable from the CLI,
   but gives a normal Xcode project if we ever need to open the GUI (e.g. for
   Interface Builder / SwiftUI previews, debugging with breakpoints).
3. **xtool** — worth a spike for build speed, but newer/less proven; would
   need its own evaluation before committing to it as the primary flow.

Next step: pick one of the above, scaffold the Swift branch, and get a
bare-bones "camera preview window" building and running from the terminal
before porting photo/video capture logic.
