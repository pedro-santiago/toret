package store

import (
	"time"

	"github.com/pedro-santiago/toret/backend/internal/httpx"
)

// Retention is how long after its date a report (and its flags) is kept.
const Retention = 30 * 24 * time.Hour

// DateKey is the sort key of a visible report in both indexes:
// "<date as RFC 3339>#<ID>". Whole-second UTC strings of equal length sort
// chronologically, which the feed queries rely on.
func DateKey(date time.Time, id string) string {
	return httpx.FormatTime(date) + "#" + id
}

// CutoffKey is the exclusive lower bound for a feed query: every DateKey of a
// report dated at or after t sorts above it.
func CutoffKey(t time.Time) string { return httpx.FormatTime(t) + "#" }

// Expiry is the TTL of a report: its date plus Retention.
func Expiry(date time.Time) time.Time { return date.Add(Retention) }
