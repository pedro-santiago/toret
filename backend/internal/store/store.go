// Package store is the persistence boundary of the API: an interface in terms
// of reports, flags, counters and the two condition caches, a DynamoDB
// implementation and an in-memory one for tests.
package store

import (
	"context"
	"errors"
	"time"
)

// ErrUnavailable wraps a storage failure that is worth retrying later (DynamoDB
// throttling, a network error). The API answers it with 503.
var ErrUnavailable = errors.New("store unavailable")

// Record is a stored report. Timestamps are whole-second UTC.
type Record struct {
	ID          string // upper-case UUID
	FountainID  string
	State       string // running, weak, dry, unknown
	Rating      *int   // 1 to 5, nil when none
	Tags        []string
	Note        string
	Date        time.Time // when the person made the report
	CreatedAt   time.Time // when the server stored it
	Author      string    // "Visitante XXXXXX"
	InstallHash string
	FlagCount   int
	Hidden      bool
	HiddenBy    string // "flags" or "owner"
	Reviewed    bool   // the owner restored it; never auto-hidden again
}

// DeleteOutcome is the result of an owner delete.
type DeleteOutcome int

const (
	// NotFound: nothing stored under that id (also an expired or deleted report).
	NotFound DeleteOutcome = iota
	// Deleted: the report existed, belonged to the caller, and is gone.
	Deleted
	// NotOwner: the report belongs to another install; nothing changed.
	NotOwner
)

// FlagOutcome is the result of a flag.
type FlagOutcome int

const (
	// FlagIgnored: no such report, already hidden, or the caller owns it.
	FlagIgnored FlagOutcome = iota
	// FlagDuplicate: this install, or this source address, already flagged it.
	FlagDuplicate
	// FlagCounted: stored and counted.
	FlagCounted
	// FlagCountedAndHidden: stored, counted, and it reached the auto-hide threshold.
	FlagCountedAndHidden
)

// HideThreshold is the number of distinct flaggers that hides a report.
const HideThreshold = 3

// FlagRequest is one flag.
type FlagRequest struct {
	ReportID    string
	InstallHash string
	IPHash      string
	Reason      string
	Now         time.Time
}

// Weather is the cached Open-Meteo reading.
type Weather struct {
	TemperatureC                 float64
	ApparentTemperatureC         float64
	RelativeHumidityPercent      int
	ApparentTemperatureMaxTodayC *float64
	ObservedAt                   time.Time
	FetchedAt                    time.Time
}

// Notice is one SMAT works order, already reduced to what the API exposes.
type Notice struct {
	ID          string
	Kind        string // waterWorks or fountainWorks
	Street      string
	FountainIDs []string
	Match       string // always "street"
	StartedOn   string // YYYY-MM-DD
	PlannedEnd  string // YYYY-MM-DD, "" when SMAT gives none
	Source      string
	FetchedAt   time.Time
}

// Notices is the cached result of one SMAT ingest.
type Notices struct {
	FetchedAt time.Time
	Items     []Notice
}

// Store is everything the API and the ingest job need from persistence. A nil
// pointer and a nil error mean "not found".
type Store interface {
	// GetReport reads a report by id, hidden ones included, strongly consistent.
	GetReport(ctx context.Context, id string) (*Record, error)
	// PutReport stores a new report; false when the id is already taken.
	PutReport(ctx context.Context, r Record) (bool, error)
	// DeleteReport removes a report if installHash owns it.
	DeleteReport(ctx context.Context, id, installHash string) (DeleteOutcome, error)
	// Feed returns visible reports dated after cutoff, newest first (ties by id
	// descending), at most limit of them.
	Feed(ctx context.Context, cutoff time.Time, limit int) ([]Record, error)
	// Fountain is Feed for one fountain.
	Fountain(ctx context.Context, fountainID string, cutoff time.Time, limit int) ([]Record, error)
	// Banned reports whether the install may not write.
	Banned(ctx context.Context, installHash string) (bool, error)
	// Flag stores a flag and applies the auto-hide rule.
	Flag(ctx context.Context, f FlagRequest) (FlagOutcome, error)
	// Incr atomically adds one to the counter under key unless it already
	// holds limit. It returns the count after the call and whether it was
	// allowed. expires is when the counter item may be deleted.
	Incr(ctx context.Context, key string, limit int, expires time.Time) (n int, allowed bool, err error)

	GetWeather(ctx context.Context) (*Weather, error)
	PutWeather(ctx context.Context, w Weather) error
	GetNotices(ctx context.Context) (*Notices, error)
	PutNotices(ctx context.Context, n Notices) error
}
