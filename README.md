# Niga

Experimental iOS 27 windowing/system-state lab for iPhone. Current target is iPhone 15 on iOS 27 developer beta 3.

## Goal

Keep the device and every app in **iPhone identity**, while selectively exposing the native multitasking/window capabilities that Apple normally gates to iPad. Full iPadOS spoofing is intentionally not the default because changing device class makes apps load iPad layouts and can destabilize the system.

## Current build

- `bad_query`-style on-device sandbox escape for supported iOS 27 betas;
- phone-safe native window capability presets: Enhanced Multitasking + Medusa floating/overlay/pinned/PiP capabilities;
- **real SpringBoard multitasking-mode switching** using the same `SBMedusaMultitaskingEnabled` / `SBChamoisWindowingEnabled` mapping used by Apple's own windowing controller;
- iOS 27 SpringBoard preferences resolver: the historical `/var/mobile/Library/Preferences/com.apple.springboard.plist` path is treated only as a legacy fast path; Niga resolves the UUID-backed MCM class-12 System Data container and falls back to `Data/System` / `Shared/SystemGroup` metadata discovery when necessary;
- resolver diagnostics in-app, including the exact resolved preferences path and access source;
- original and pre-change MobileGestalt/SpringBoard backups, verified in-place writes and recovery;
- **Apply + Respring**, **Enable Windowed Apps + Respring**, **Stage Manager + Respring**, and stock restore;
- app-container discovery and file browser with backup-before-replace/delete;
- per-app profiles: width, height, X/Y, independent portrait/landscape/automatic orientation, always-on-top intent and launch-windowed intent;
- geometry presets for portrait, landscape video, rails, square and large windows;
- saved multi-app workspaces and one-tap opening of workspace apps;
- expanded read-only FrontBoard/RunningBoard probe: runtime class/selector discovery, current UI idiom/scene geometry, running-app process handle test and post-signing entitlement report;
- direct external-scene experiment with typed frame/orientation setters and frame read-back verification;
- Data/System + Shared/SystemGroup explorer and scene-state miner;
- experiment history for recording which capability combination actually works on-device.

## Why v0.6.1 failed on iOS 27 DB3

The screenshot from the target device returned `SpringBoard preferences grant failed: -3`. In Niga's sandbox layer, `-3` means ContainerManager returned no object for that path. Upstream `bad_query` documents iOS 27 access to MCM-backed roots such as `/var/containers/Data/System` and `/var/containers/Shared/SystemGroup`; it does not list the old global `/var/mobile/Library/Preferences` directory. The resolver now finds SpringBoard's actual container instead of pretending that the legacy path is universally reachable.

## Per-app orientation / geometry

Profiles and UI are implemented. Direct enforcement uses FrontBoard/RunningBoard runtime discovery and now verifies the scene frame after mutation instead of reporting success merely because `updateSettingsWithBlock:` returned. Normal sideload signing may still block access to external scenes; the system-state miner is the fallback research path when that happens.

See `Research/FRONTBOARD.md`.

## Build policy

GitHub Actions builds only when `.build-trigger` changes or when manually dispatched. Ordinary source commits do not burn macOS runner minutes. The workflow has a single concurrency group so two IPA builds cannot run at once. The output is an unsigned IPA intended for user-controlled sideload signing.
