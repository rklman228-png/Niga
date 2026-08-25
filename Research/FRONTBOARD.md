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
2. build or locate an `FBScene`;
3. use mutable application-scene settings;
4. set `frame`, `deviceOrientation`, `interfaceOrientation`, safe-area/periphery values and presentation level;
5. call `updateSettingsWithBlock:` to resize/rotate a live external app scene.

Niga now has an experimental **Live Scene Lab** that tries the lower-risk variant first: it does not launch a foreign process through privileged FrontBoard APIs. The user opens the app normally, Niga resolves its RunningBoard PID, enumerates scenes visible through `FBSceneManager`, matches by PID/identifier, then asks the matched scene to update only its frame/orientation/level. Every stage returns JSON diagnostics.

## What TrollPad teaches us

TrollPad is useful because it shows why full iPad spoofing works while also showing why it is ugly. Its SpringBoard tweak does not permanently need every app to identify as an iPad. Instead, several SpringBoard code paths temporarily return an iPad idiom only while Apple multitasking logic runs, then immediately restore the normal iPhone idiom.

Relevant findings:

- SpringBoard has additional idiom checks around full-screen switcher overlays and main switcher content, beyond the MobileGestalt capability bits.
- Medusa support is separately forced at the SpringBoard policy layer (`isMedusaEnabled`, app capability checks, platform Medusa capabilities).
- Stage Manager grid widths/heights can be extended down to about 150 points; smaller sizes are documented by the tweak author as crash-prone.
- the maximum on-stage app count is policy-driven (the tweak raises it to 5).
- orientation handling has separate scene-participant and supported-orientation paths.
- resize-corner policy is independently controllable.

This makes two things clear for a non-jailbroken/sideloaded build: MobileGestalt flags are the correct first layer, but if an iPhone-only SpringBoard check still blocks a feature, the remaining options are a direct scene path that survives signing or a writable SpringBoard/FrontBoard state path exposed by the sandbox escape. Globally turning every process into an iPad is deliberately not Niga's default solution.

## Signing gate

Published external-scene launchers are platform/TrollStore-style and ask for private entitlements including FrontBoard launch, RunningBoard launch/target/process-state/assertion privileges, SpringBoard UI client, QuartzCore displayable context, BackBoard client, platform-application and no-sandbox.

Niga is intended to remain usable as a normal sideloaded IPA, so it does not assume those entitlements survive signing. The Scene Probe dynamically loads the relevant private frameworks and reports:

- presence of the scene/process classes;
- interesting instance/class selectors containing scene/frame/size/orientation/settings/host/present/window/update/geometry/stage/multitask terms;
- whether a process identity/handle can be resolved for an already-running target;
- the exact private entitlements present after installation;
- the current app's `userInterfaceIdiom`, screen bounds and connected `UIWindowScene` geometry.

The Live Scene Lab then attempts the real external-scene update. That distinguishes four cases on the exact device: API missing, process lookup blocked, external scene hidden, or scene update accepted.

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
