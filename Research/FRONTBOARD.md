# FrontBoard / per-app window control research

## What is confirmed

LiveContainer and FrontBoardAppLauncher demonstrate that external application processes can be presented through private FrontBoard/UIKit scene APIs. The core path is:

1. Obtain an `RBSProcessIdentity` / `RBSProcessHandle` for the target process.
2. Create `FBSMutableSceneDefinition` + `FBSMutableSceneParameters`.
3. Create or host an `FBScene` for that process.
4. Update `UIMutableApplicationSceneSettings.frame`, `interfaceOrientation`, `deviceOrientation`, safe-area values, and other scene settings.
5. Present the scene with a `_UIScenePresenter` / `_UISceneHostingController`.

That is the mechanism we ultimately want for per-app width/height/position/orientation.

## MobileGestalt key separation

The previously opaque iPadOS keys are now separated by meaning:

- `qeaj75wk3HF4DwQ8qbIi7g` — Stage Manager capability.
- `mG0AnH/Vy1veoqoLRAIgTA` — Medusa floating live-app capability.
- `UCG5MkVahJxG1YULbbd5Bg` — Medusa overlay-app capability.
- `ZYqko/XM5zD3XBfN5RmaXA` — Medusa pinned-app capability.
- `nVh/gwNpy7Jv1NOk00CMrw` — Medusa PiP/mirroring capability.
- `uKc7FPnEO++lVhHWHFlGbQ` — **iPad identity flag**, not a generic windowing flag.
- `mtrAoWJ3gsq+I90ZnQ0vQw` — DeviceClassNumber; the full iPadOS tweak changes it from the iPhone value to the iPad class.

The phone-preserving preset therefore enables Stage Manager + the four Medusa capabilities and explicitly removes the `ipad` identity override. It never touches DeviceClassNumber. This is the key difference from enabling the full iPadOS UI.

## The signing problem

FrontBoardAppLauncher explicitly requires TrollStore and is signed with private entitlements including `com.apple.frontboard.launchapplications`, multiple RunningBoard entitlements, `com.apple.springboard-ui.client`, QuartzCore displayable-context, `platform-application`, and no-sandbox.

A normally sideloaded Niga build cannot assume those entitlements survive signing. Therefore v0.3+ includes a read-only Scene Probe that checks the exact iOS 27 beta 3 runtime and the entitlements actually present after the user's signer installs the app.

## Current strategy

Niga has two independent paths:

- **Phone-preserving native windowing:** expose Stage Manager + Medusa window capabilities while deliberately removing the iPad identity override and leaving DeviceClassNumber untouched.
- **Direct per-app scene control research:** probe FrontBoard/RunningBoard availability and entitlement gates. If direct scene APIs are blocked, scan accessible `Data/System` and `Shared/SystemGroup` containers for persistent SpringBoard/FrontBoard scene/window state that can be modified through the iOS 27 sandbox escape instead.

## Safety / recovery

Every MobileGestalt mutation is preceded by a backup. The first successful MobileGestalt access creates an original snapshot. Recovery can restore that original snapshot and respring from inside Niga.
