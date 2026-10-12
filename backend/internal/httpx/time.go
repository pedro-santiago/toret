package httpx

import "time"

// FormatTime is the wire format of every timestamp: RFC 3339, UTC, whole
// seconds ("2026-10-12T09:41:00Z"). Swift's .iso8601 decoder rejects fractions
// and Go's default marshalling emits nanoseconds, so never marshal time.Time.
func FormatTime(t time.Time) string {
	return t.UTC().Truncate(time.Second).Format(time.RFC3339)
}

// ParseTime reads an RFC 3339 timestamp, fractions and numeric offsets
// included, and normalises it to whole-second UTC.
func ParseTime(s string) (time.Time, error) {
	t, err := time.Parse(time.RFC3339, s)
	if err != nil {
		return time.Time{}, err
	}
	return t.UTC().Truncate(time.Second), nil
}
