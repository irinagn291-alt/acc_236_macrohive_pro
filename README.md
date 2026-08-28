# MacroHive

One hive, many eaters. MacroHive is an offline-first calorie and macro tracker for a household that shares a kitchen but not a metabolism. Each local family profile keeps its own targets, harvest log and wish comb. There are no accounts, no ads and no analytics. Nutrition data comes from [Open Food Facts](https://world.openfoodfacts.org). MacroHive is a personal food log, not medical advice.

## Architecture

The app is a **RIBs-like** tree (Router / Interactor / Builder) on a local Swift package, `Packages/HiveRIBs`.

A household food log is a graph of short-lived tasks — forage, assign, switch member — hanging off one long-lived hive. RIBs maps that graph: a parent router owns child lifecycles, interactors hold business rules, and listeners only point upward. Expanding an accordion section attaches a child RIB; collapsing it detaches the child. Search, scan, detail and assign never push a new screen; they are panes inside the Forage child.

`HiveRIBs` exposes only `CombInteractor`, `CombRouter`, `CombBuildable` and the attach/detach lifecycle. UIKit stays in the app target. Persistence is `CombHiveStore` (SQLite C API). Networking is `NectarClient`. Views never see a statement or a DTO.

## Family profiles

This is why a household would pick MacroHive. Several local members share the device. Each has partitioned rows (`profile_id` + day key `YYYYMMDD`). Switching is instant and local. Today’s comb shows member chips and a honeycomb of adherence so the hive can see who is on target. Covered by `HiveMemberTests` and `SwarmInteractorTests`.

## Design

Direction: **apiary honeycomb**, isometric 3D art, Charter Roman/Bold, light palette (`mhv_background` `#FFF8E1`, `mhv_surface` `#FFFFFF`, `mhv_ink` `#3B2F0B`, `mhv_accent` `#F2A900`, `mhv_muted` `#A38F5B`). Honeycomb grids, macro cells and progress combs are `CALayer` subclasses (`draw(in:)` / `CAShapeLayer`), animated with `CABasicAnimation` / `CAKeyframeAnimation`.

Navigation is a single accordion. Horizon Plan looks **14 days** ahead. Nectar Drop is eaten-only; a future date remaps it to Midday Forage.

## How this app differs

Unlike the 18AUG reference batch, MacroHive has no push navigation, no SwiftUI screens, no ORM, and no single-user assumption. Depth is expansion. Storage is raw `libsqlite3` with bound parameters, WAL, foreign keys and `PRAGMA user_version`. The scanner is Vision on the live buffer, inline in the accordion, with sample barcodes on Simulator. Family profiles are the twist, not a settings footnote.

## Build

```bash
cd App14_MacroHive
xcodegen generate
xcodebuild -scheme MacroHive -destination 'generic/platform=iOS Simulator' CODE_SIGNING_ALLOWED=NO build
xcodebuild -scheme MacroHive -destination 'platform=iOS Simulator,name=iPhone 16' CODE_SIGNING_ALLOWED=NO test
```

Requires Xcode with iOS 17 SDK, Swift 6.2, `SWIFT_STRICT_CONCURRENCY=complete`. No CocoaPods, no CI, no Alamofire.

Contact: https://macrohive.pro/contact-us

User-Agent: `MacroHive/1.0 (iOS; +https://macrohive.pro)`

## Asset prompts

Base prompt, reused and extended:

`isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render`

| Asset | Prompt |
| --- | --- |
| `mhv_AppIcon` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, the app's single emblem, centred, filling the canvas edge to edge |
| `mhv_Splash` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a vertical hero composition with a calm, uncluttered centre band |
| `mhv_Onboarding1` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a person or object representing discovering what is in packaged food |
| `mhv_Onboarding2` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a scanning or measuring motif showing a product being identified |
| `mhv_Onboarding3` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a goal or target motif showing daily progress being met |
| `mhv_EmptyLog` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, an empty vessel, surface or container waiting to be filled |
| `mhv_EmptySearch` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a search motif that has come back with nothing found |
| `mhv_EmptyPlan` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, an empty schedule, grid or horizon with nothing scheduled |
| `mhv_EmptyWish` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, an empty basket, list or shelf |
| `mhv_SlotFirstForage` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a morning motif appropriate to the theme |
| `mhv_SlotMiddayForage` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a midday motif appropriate to the theme |
| `mhv_SlotEveningForage` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, an evening motif appropriate to the theme |
| `mhv_SlotNectarDrop` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a small extra or in-between motif appropriate to the theme |
| `mhv_MacroProtein` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a symbol standing for protein, rendered as a single clear emblem |
| `mhv_MacroCarbs` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a symbol standing for carbohydrate, rendered as a single clear emblem |
| `mhv_MacroFat` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a symbol standing for dietary fat, rendered as a single clear emblem |
| `mhv_ProductPlaceholder` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a generic packaged grocery item with no readable branding |
| `mhv_CardBackdrop` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, an abstract backdrop suitable for sitting behind a product card |
| `mhv_Texture` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a seamless repeating surface pattern |
| `mhv_ControlFace` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, the face of a single physical control such as a dial, key or slider handle |
| `mhv_ScanOverlay` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a framing reticle or targeting bracket, open in the middle |
| `mhv_TwistHero` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, an emblem representing this app's signature feature |
| `mhv_SuccessMark` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a confirmation mark or celebratory emblem |
| `mhv_HeaderDecor` | isometric 3d illustration, honeycomb hexagonal cells, warm honey amber and dark brown, soft ambient occlusion, clean vector-like render, a wide decorative band or ornament |
