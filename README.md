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
- **Apply + Respring**, **Restore + Respring**, and standalone **Respring** controls in-app;
- app-container discovery and file browser with backup-before-replace/delete;
- per-app profiles: width, height, X/Y, independent portrait/landscape/automatic orientation, always-on-top intent and launch-windowed intent;
- geometry presets for portrait, landscape video, rails, square and large windows;
- saved multi-app workspaces and one-tap opening of the workspace apps;
- expanded FrontBoard/RunningBoard probe: runtime class/selector discovery, current UI idiom/scene geometry, running-app process handle test and post-signing entitlement report;
- **Live Scene Lab**: opens a target app, resolves its RunningBoard PID, enumerates visible FrontBoard scenes, matches the target scene, and experimentally applies frame/orientation/scene-level changes without changing iPhone identity;
- Live Scene Lab returns structured JSON for every failure stage so a normal sideload-signing block is distinguishable from a missing private API;
- Data/System + Shared/SystemGroup explorer;
- scene-state miner that searches accessible system containers for window/scene/stage/workspace/FrontBoard/SpringBoard/Medusa/orientation/geometry persistence;
- experiment history for recording which capability combination actually works on-device.

## Per-app orientation / geometry

The per-app profile model and live mutation path are both implemented. Live Scene Lab uses the same private scene family that known external-scene launchers use: RunningBoard identifies the target process, `FBSceneManager` enumerates scenes, and a matched scene is asked to update mutable application-scene settings. The app itself remains an iPhone app; Niga does not globally spoof its idiom for this route.

Normal sideload signing may still prevent a process from seeing or mutating another application's scene because public jailbreak/TrollStore implementations rely on private FrontBoard/RunningBoard entitlements. Niga therefore reports the exact runtime/entitlement state and keeps the System State miner as a second route for writable persistent scene/window state exposed by the iOS 27 sandbox escape.

See `Research/FRONTBOARD.md`.

## Build policy

GitHub Actions builds only when `.build-trigger` changes or when manually dispatched. Ordinary source commits do not burn macOS runner minutes. The workflow has a single concurrency group so two IPA builds cannot run at once. The output is an unsigned IPA intended for user-controlled sideload signing.
