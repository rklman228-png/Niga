# Niga

Experimental iOS 27 windowing/system-state lab for iPhone. Current target is iPhone 15 on iOS 27 developer beta 3.

## Goal

Keep the device and every app in **iPhone identity**, while selectively exposing the native multitasking/window capabilities that Apple normally gates to iPad. Full iPadOS spoofing is intentionally not the default because changing device class makes apps load iPad layouts and can destabilize the system.

## Current build

- `bad_query`-style on-device sandbox escape for supported iOS 27 betas;
- phone-safe native window preset: Stage Manager / Enhanced Multitasking + Medusa floating/overlay/pinned/PiP capabilities;
- capability-isolation matrix for finding the smallest set that enables native resizable windows;
- unsafe iPad identity switch separated from the phone-safe controls;
- original and pre-change MobileGestalt backups, verified writes, diff and emergency restore;
- **Apply + Respring** and **Restore + Respring** buttons in-app;
- app-container discovery and file browser with backup-before-replace/delete;
- per-app profiles: width, height, X/Y, independent portrait/landscape/automatic orientation, always-on-top intent and launch-windowed intent;
- geometry presets for portrait, landscape video, rails, square and large windows;
- saved multi-app workspaces and one-tap opening of the workspace apps;
- expanded read-only FrontBoard/RunningBoard probe: runtime class/selector discovery, current UI idiom/scene geometry, running-app process handle test and post-signing entitlement report;
- Data/System + Shared/SystemGroup explorer;
- scene-state miner that searches accessible system containers for window/scene/stage/workspace/FrontBoard/SpringBoard/Medusa/orientation/geometry persistence;
- experiment history for recording which capability combination actually works on-device.

## Per-app orientation / geometry

Profiles and UI are implemented. The remaining enforcement path depends on what survives normal sideload signing on the exact device. Published external-scene implementations use private FrontBoard/RunningBoard entitlements, so Niga first proves the available runtime surface instead of blindly calling privileged APIs. If direct scene mutation is blocked, the System State miner is designed to locate writable persistent SpringBoard/FrontBoard state exposed by the iOS 27 sandbox escape.

See `Research/FRONTBOARD.md`.

## Build policy

GitHub Actions builds only when `.build-trigger` changes or when manually dispatched. Ordinary source commits do not burn macOS runner minutes. The workflow has a single concurrency group so two IPA builds cannot run at once. The output is an unsigned IPA intended for user-controlled sideload signing.
