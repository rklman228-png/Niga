# Niga

Experimental on-device windowing lab for iPhone 15 / iOS 27 developer beta 3.

## Goal

Use iOS's native multi-window stack **without globally turning the phone into an iPad**. Apps should continue seeing an iPhone while SpringBoard receives only the capabilities and windowing-mode requests needed for resizable/multi-app windows.

## Current architecture

1. The MobileGestalt layer enables the phone-safe multitasking capabilities and explicitly keeps the iPad identity override off.
2. Niga loads `SpringBoardServices.framework` at runtime.
3. Windowing mode is requested through Apple's own `SBSRequestUpdateSwitcherWindowingMode` service path instead of editing `com.apple.springboard.plist`.
4. Mode mapping is native SpringBoard behavior: `0 = Full Screen`, `1 = Windowed Apps`, `2 = Stage Manager`.
5. The main buttons respring only after the SpringBoardServices completion callback. Missing acknowledgement becomes a visible timeout/error instead of a fake success.

The direct system-service route replaced the v0.6/v0.7 preferences resolver after on-device testing showed that `/var/mobile/Library/Preferences/com.apple.springboard.plist` is outside the usable sandbox-escape path set on this beta.

## Included labs

- phone-safe MobileGestalt capability presets and backup/restore;
- native Windowed Apps / Stage Manager / Full Screen requests through SpringBoardServices;
- SpringBoard window-layout reset request;
- respring control;
- app-container discovery and file browser;
- per-app window profiles with width, height, X/Y, portrait/landscape/automatic orientation and always-on-top intent;
- geometry presets;
- saved multi-app workspaces;
- FrontBoard/RunningBoard scene probe;
- direct external-scene frame/orientation experiment with actual frame read-back verification;
- Data/System and Shared/SystemGroup exploration;
- scene-state mining and capability experiment history.

Per-app direct scene mutation is still experimental because normal sideload signing may limit visibility/control of another app's FrontBoard scene. The global native Windowed Apps request and per-app scene control are intentionally separate layers.

## Build policy

GitHub Actions builds only when `.build-trigger` changes or when manually dispatched. Ordinary source commits do not consume a build. One concurrency group prevents parallel IPA builds. The workflow outputs an unsigned IPA for user-controlled sideload signing.
