# Contributing

Issues and pull requests are welcome.

## Fountain data is not fixed here

The catalogue comes from OpenStreetMap. If a fountain is missing, misplaced or
tagged wrongly, fix it on [openstreetmap.org](https://www.openstreetmap.org)
(tag `amenity=drinking_water`, plus `fountain=toret` for the cast-iron ones,
`bottle=yes`, `dog=yes`, `wheelchair=yes|limited|no` where true). Then run
`python3 tools/build-catalogue.py` and open a pull request with the regenerated
`Shared/Resources/fountains.json`. Edits made only to that file are lost on the
next rebuild.

## Code

- Xcode 26 or later, iOS 26 deployment target, Swift 6.
- The Xcode project is generated: edit `project.yml`, then `make generate`.
  Don't hand-edit `Toret.xcodeproj`.
- `make test` must pass. Add a Swift Testing test for any logic you change.
- Match the surrounding code: comments explain why, not what.
- Strings are Portuguese (Brazil) for now. Wrap any string that is not a
  SwiftUI `Text` literal in `String(localized:)` so it can be extracted later.
- The app must never claim water is running without a dated community report
  behind it. That rule is the point of the app.

## Never commit

`local.mk`, `.p8` keys, provisioning profiles, or anything under `build/`.
