# Niga

Experimental iOS 27 windowing lab for supported development betas.

Target: iPhone 15 / iOS 27 beta 3.

The first build focuses on a phone-preserving native windowing experiment: Stage Manager/window capability flags are applied without switching the device idiom to iPad. It also includes MobileGestalt backup/restore, before/after diffs, app-container discovery, per-app window profile storage, and an in-app respring button.

## Build

GitHub Actions only builds when `.build-trigger` changes (or when manually dispatched), so normal source commits do not waste runner minutes. The artifact is an unsigned IPA intended for sideloading/signing by the user.
