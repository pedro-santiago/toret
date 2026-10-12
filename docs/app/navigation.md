# Navigation

All of it lives in two files: `Toret/Screens/RootView.swift` (structure and URL router)
and `Toret/State/ToretModel.swift` (the state it reads). The URL grammar is in
`Shared/Model/DeepLink.swift`.

## Structure

```
RootView
 |- one NavigationStack per tab  (Mapa | Perto | Relatos | Salvas | Ajustes)
 |    '- pushed: Route.detail(fountain)   (the only pushed route)
 |- ToretTabBar                  (custom, flat, always visible at the bottom)
 |- fullScreenCover: CompassScreen         <- model.showingCompass
 |- fullScreenCover: RouteScreen           <- model.walkingTo (a Fountain)
 |- sheets: ReviewSheet (from the community section), BlockedAuthorsSheet (from Relatos)
 '- overlay: LaunchOverlay (once per process, ignores touches)
```

Walking is deliberately a full-screen cover, not a pushed page: turn-by-turn is a mode
you leave, and nothing else should compete for the display while you move
(`Route` doc comment, `ToretModel.swift`).

## The tab bar

`Toret/Components/ToretTabBar.swift`.

- Five tabs in this order: Mapa, Perto, Relatos, Salvas, Ajustes (`Tab.allCases`).
  Note that the `Tab` enum lists `community` before `saved`, matching this order.
- Default tab on launch: Mapa. Tab selection is **not** restored between launches.
- Tapping an unselected tab selects it. **Tapping the selected tab pops that tab to its
  root** (`onReselect` -> `model.popToRoot(tab)`). There is no scroll-to-top.
- The selected tab gets the sun disc behind its glyph; it slides between tabs with a
  spring (a short ease-out under Reduce Motion) via `matchedGeometryEffect`.
- Selection gives a haptic (`.sensoryFeedback(.selection)`). Each tab is a button with
  its title as the accessibility label and the `isSelected` trait.
- Only the selected tab's screen is in the view hierarchy (a `switch` in
  `RootView.body`), so switching away discards that screen's local state such as scroll
  position, but **keeps its navigation path**, which is held in `model.paths[tab]`.

## Per-tab stacks

Each tab owns a `NavigationStack(path:)` bound to `model.paths[tab]`. The only
destination is `Route.detail(Fountain)` -> `DetailScreen`. Detail rows exist on:

| Tab | Pushes detail from |
| --- | --- |
| Mapa | the selected-fountain plate (`model.push(.detail, in: .map)`) |
| Perto | a row |
| Relatos | a report row's fountain |
| Salvas | a row |
| any | "other fountains nearby" on a detail page pushes another detail onto the *current* tab |

Detail hides the system navigation bar and draws its own pinned back and save buttons
(`DetailScreen`), so the way out never scrolls away.

## Presentations over everything

| Presentation | State | Opened by |
| --- | --- | --- |
| Compass | `model.showingCompass` | Map's compass button; `toret://compass[/nearest]` |
| Walk route | `model.walkingTo` | "Traçar rota" on map plate, detail, long-press menu of a saved row; `toret://route/...`; notification tap |
| Review sheet | local `composing` | "Avaliar esta fonte" on a detail page |
| Blocked authors | local `showingBlocked` | link at the foot of Relatos |

## Deep links (`toret://`)

Widgets, Control Center controls, Siri, Shortcuts, the Live Activity and the
proximity notification all arrive at `RootView.open(_:)` through `.onOpenURL`. Anything
that does not parse is ignored (`DeepLink.init?(url:)`); an unknown fountain id is also
ignored silently.

| URL | Sent by | Lands on |
| --- | --- | --- |
| `toret://fountain/<osm id>` | Widget tap (any size, and each row of the large one) | Closes compass and walk; selects the Mapa tab, pops it to root, selects the fountain, pushes its detail |
| `toret://route/<osm id>` | Live Activity / Dynamic Island tap | Closes the compass, selects the fountain, opens the walk route on it |
| `toret://route/nearest` | "Rota até a fonte" control; Siri "Traçar rota até a fonte" | Waits for a fix, then walks to the nearest **non-dry** fountain (`nearestUsable(1)`) |
| `toret://compass` | (grammar only) | Compass on whatever is selected; closes any walk |
| `toret://compass/nearest` | "Fonte mais próxima" control; Siri "Abrir a bússola" | Waits for a fix, selects the nearest non-dry fountain, opens the compass |

"Waits for a fix" means up to 3 seconds (30 x 100 ms) while `LocationStatus` is
`.searching`, then one more 60 ms tick so the fix reaches the model's distances.
With no fix coming (denied, outside Turin) it does not wait and the nearest is
measured from the anchor.

**Proximity notification tap** is not a URL: `NotificationRouter` stores the fountain id
from the notification's `userInfo`, `RootView.onChange(of: router.pendingID)` selects the
Mapa tab, selects the fountain and opens the walk route ("Toque para traçar a rota").
Unlike the deep links it does not reset `showingCompass`; what SwiftUI does with a route
cover requested while the compass cover is open has not been checked.

The Siri phrases and the widget gallery names live in localized catalogs
([localization-ux.md](localization-ux.md)).

## State restoration

What persists (`Preferences` in `Shared/Model/Store.swift`, in the shared app group):

- the saved fountain IDs;
- the map filters (`notDry`, `accessible`, `bottle`, `dogs`; stored by raw value, older
  Portuguese titles are still read);
- the two switches (Bússola sempre visível, Avisar ao passar perto);
- the **selected fountain** and, derived from it, the map camera centre and needle.

What does **not** persist: the current tab (always Mapa), every tab's navigation path
(`paths = [:]`), the compass or walk being open, search text, scroll positions, the
review draft. There is no `SceneStorage`. A walk that the system left behind when the
app was killed is ended on next launch (`WalkActivityController.endOrphans()`).

When the app returns to the foreground it reloads saved IDs, in case Siri saved a
fountain while it slept (`reloadExternalPreferences`), and refreshes the community and
conditions.

## Launch arguments (Debug builds only)

These exist so a script can reach screens the simulator cannot tap to. **None of them
does anything in a Release build**: each read is inside `#if DEBUG` (or the whole type
is). Pass them after the bundle id: `xcrun simctl launch <udid> br.tec.nuance.toret <args>`.

| Argument | Values | Read in | Debug-only |
| --- | --- | --- | --- |
| `-toret-screen` | `mapa` (default for any other value), `perto`, `relatos`, `salvas`, `ajustes`, `bussola`, `detalhe` (selected fountain), `rota` (selected fountain), `skyline`, `vazios` | `RootView.openScreenFromLaunchArguments` | yes |
| `-toret-launch` | flag | `LaunchOverlay`: play the launch poster even with `-toret-screen` | yes |
| `-toret-launch-slow` | factor, e.g. `8` | `LaunchOverlay`: play it N times slower (also forces it with `-toret-screen`) | yes |
| `-toret-heading` | degrees | `LocationProvider.start`: pin the compass heading (no magnetometer in the simulator) | yes |
| `-toret-tilt` | `x,y` in -1...1 | `TiltProvider`: pin the parallax tilt | yes |
| `-toret-scroll` | a number (points), `fim` (foot of a long screen), or the bare word `meio` anywhere in the arguments (Detail scrolls to 900 pt) | `NearbyScreen`, `Screen.swift` (`fim`), `DetailScreen` (`meio`) | yes |
| `-toret-skyline` | page `0...5` | `SkylineGallery` (itself Debug-only) | yes |
| `-toret-vazio` | scene index | `EmptyGallery` (itself Debug-only) | yes |
| `-toret-compose` | flag | `CommunitySection`: open the review sheet | yes |
| `-toret-focus-community` | flag | `CommunitySection`: scroll the community section into view | yes |
| `-toret-seed-reports` | flag | `CommunityHooks`: add demo reports to the device-only backend | yes |
| `-toret-api` | URL (`http`/`https`) | `APIConfiguration`: use that server instead of the device file | yes |
| `-toret-submit-test` | flag | `CommunityHooks`: post one test report (needs `-toret-api`) | yes |
| `-toret-delete-test` | flag | `CommunityHooks`: delete the test report again | yes |

Not a launch argument but useful: `-AppleLanguages "(it)"` runs the app in Italian
([../localization.md](../localization.md)).

`make run` boots the simulator, sets the location to central Turin and launches with no
arguments; screenshots per language are `tools/l10n-screenshots.sh`.
