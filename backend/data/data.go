// Package data embeds the fountain catalogue the API validates against.
//
// fountains.json is a copy of Shared/Resources/fountains.json (the app's
// catalogue, the single source of truth). `make data` refreshes it and a test
// fails when the two drift.
package data

import _ "embed"

//go:embed fountains.json
var Fountains []byte
