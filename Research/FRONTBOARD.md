# FrontBoard / native phone-windowing research

## Confirmed split in the iPadOS spoof

Mond's full iPadOS mode mixes actual multitasking capabilities with device-identity spoofing. Niga separates them:

- `qeaj75wk3HF4DwQ8qbIi7g` — Enhanced Multitasking / Stage Manager capability.
- `mG0AnH/Vy1veoqoLRAIgTA` — Medusa floating live-app capability.
- `UCG5MkVahJxG1YULbbd5Bg` — Medusa overlay-app capability.
- `ZYqko/XM5zD3XBfN5RmaXA` — Medusa pinned-app capability.
- `nVh/gwNpy7Jv1NOk00CMrw` — Medusa PiP capability.
- `uKc7FPnEO++lVhHWHFlGbQ` — iPad identity flag.
- `mtrAoWJ3gsq+I90ZnQ0vQw` — DeviceClassNumber; full iPadOS mode changes the phone class to the iPad class.

The phone-safe presets always remove `uKc...` and never modify DeviceClassNumber. An isolation matrix progressively enables Stage/Medusa capabilities so the minimum native-window set can be found empirically on iOS 27 beta 3.

## Direct external-scene path

Public FrontBoardAppLauncher / LiveContainer-derived code proves the geometry mechanism itself:

1. resolve an `RBSProcessIdentity` and running `RBSProcessHandle`;
2. build `FBSMutableSceneDefinition` and `FBSMutableSceneParameters`;
3. create/attach an `FBScene`;
4. set `UIMutableApplicationSceneSettings.frame`, `deviceOrientation`, `interfaceOrientation`, safe-area/periphery values and presentation level;
5. call `updateSettingsWithBlock:` to resize/rotate a live external app scene;
6. host/present through the scene presentation manager / private UIKit presentation objects.

That is exactly the API family needed for independent per-app portrait/landscape and geometry.

## Signing gate

The published launcher is platform/TrollStore-style and asks for private entitlements including FrontBoard launch, RunningBoard launch/target/process-state/assertion privileges, SpringBoard UI client, QuartzCore displayable context, BackBoard client, platform-application and no-sandbox.

Niga is intended to remain usable as a normal sideloaded IPA, so it does not assume those entitlements survive signing. The Scene Probe dynamically loads the relevant private frameworks and now reports:

- presence of the scene/process classes;
- interesting instance/class selectors containing scene/frame/size/orientation/settings/host/present/window/update/geometry/stage/multitask terms;
- whether a process identity/handle can be resolved for an already-running target;
- the exact private entitlements present after installation;
- the current app's `userInterfaceIdiom`, screen bounds and connected `UIWindowScene` geometry.

This lets us distinguish "API does not exist" from "API exists but the signature is not privileged enough" on the exact beta.

## Writable-state fallback

`bad_query` on iOS 27 exposes `Data/System` and `Shared/SystemGroup` containers in addition to normal application containers. Niga's System State explorer enumerates those containers and the Scene State Miner recursively searches readable small files for names/content related to:

`scene`, `window`, `stage`, `workspace`, `frontboard`, `springboard`, `medusa`, `orientation`, `geometry`, `layout`, `floating`, `multitask`.

The intended on-device experiment is:

1. snapshot/find candidate state;
2. perform one native window operation;
3. scan/diff again;
4. identify a persistent writable field for scene geometry/orientation;
5. wire that field to the per-app profile system.

## Recovery invariant

Every MobileGestalt mutation takes a pre-change backup. First successful access stores an original snapshot. Writes are parsed and re-read byte-for-byte after writing; a verification failure attempts immediate rollback. Recovery exposes original restore plus one-tap respring.
