# Niga

Experimental iOS 27 windowing and system-state lab for supported development betas.

Target: iPhone 15 / iOS 27 beta 3.

## Current features

- phone-preserving Stage Manager/window capability experiment without switching the device to iPad idiom;
- individual MobileGestalt capability toggles;
- original + pre-change MobileGestalt backups, restore and diff;
- in-app respring;
- app-container discovery through the iOS 27 `bad_query` sandbox escape;
- data-container browser with plist/JSON/text preview, replace-with-backup and delete-with-backup;
- per-app profiles for width, height, X/Y, orientation and future always-on-top enforcement;
- saved multi-app workspaces;
- capability experiment history;
- read-only FrontBoard/RunningBoard scene probe for the exact installed signature/runtime;
- scanner for accessible `Data/System` and `Shared/SystemGroup` containers, used as a fallback research path when direct FrontBoard scene control is entitlement-gated.

Per-app scene geometry/orientation enforcement is intentionally not claimed as complete yet. Existing public FrontBoard implementations rely on private entitlements normally available through TrollStore/platform signing. Niga probes what survives normal sideload signing on iOS 27 beta 3 before attempting scene mutation. See `Research/FRONTBOARD.md`.

## Build

GitHub Actions builds only when `.build-trigger` changes or when manually dispatched. Ordinary source commits do not consume macOS runner minutes. A concurrency group prevents simultaneous IPA builds. The artifact is an unsigned IPA intended for user-controlled sideload signing.
