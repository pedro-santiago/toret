// Package reports is the domain of a community report: what a client may send,
// how it is validated, how it is shown on the wire and how reports add up to a
// per-fountain summary. Everything here is a function of its arguments, so it
// is tested without a store or an HTTP request.
package reports

import (
	"bytes"
	"encoding/json"
	"io"
	"regexp"
	"strconv"
	"strings"
	"time"
	"unicode"
	"unicode/utf8"

	"github.com/pedro-santiago/toret/backend/internal/catalogue"
	"github.com/pedro-santiago/toret/backend/internal/httpx"
	"github.com/pedro-santiago/toret/backend/internal/store"
)

// Limits of section 4 and 6.4.
const (
	MaxNoteCodePoints = 280
	MaxTags           = 3
	PastWindow        = 30 * 24 * time.Hour
	FutureWindow      = 10 * time.Minute
	// Freshness is CommunitySummary.freshness: how long a report speaks for the water.
	Freshness = 36 * time.Hour
)

// The closed enums of v1.
var (
	states = map[string]bool{"running": true, "weak": true, "dry": true, "unknown": true}
	tags   = map[string]bool{"cold": true, "clean": true, "strongFlow": true, "easyToReach": true, "shade": true, "dirty": true, "hardToFind": true}
)

// FlagReasons are what ReportRow sends.
var FlagReasons = map[string]bool{"offensive": true, "spam": true, "false": true}

var uuidPattern = regexp.MustCompile(`^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$`)

// NormaliseID returns the upper-case form of a UUID, or false.
func NormaliseID(id string) (string, bool) {
	if !uuidPattern.MatchString(id) {
		return "", false
	}
	return strings.ToUpper(id), true
}

// Rejection is a validation failure, mapped 1:1 onto an error body.
type Rejection struct {
	Status int
	Code   string
	Field  string
	Reason string
}

func reject(code, field, reason string) *Rejection {
	return &Rejection{Status: 422, Code: code, Field: field, Reason: reason}
}

// Draft is a validated report, before the server adds author and install.
type Draft struct {
	ID         string
	FountainID string
	State      string
	Rating     *int
	Tags       []string
	Note       string
	Date       time.Time
}

// Validate parses a POST /v1/reports body and applies section 6.4 in order;
// the first failure wins. Unknown members, author and isMine included, are
// ignored. A body that is not one JSON object is a 400.
func Validate(body []byte, cat *catalogue.Catalogue, now time.Time) (Draft, *Rejection) {
	var raw map[string]json.RawMessage
	dec := json.NewDecoder(bytes.NewReader(body))
	if err := dec.Decode(&raw); err != nil || raw == nil || dec.Decode(&struct{}{}) != io.EOF {
		return Draft{}, &Rejection{Status: 400, Code: "bad_request"}
	}
	var d Draft

	// 1. id
	id, ok := stringField(raw, "id")
	if d.ID, ok = NormaliseID(id); !ok {
		return d, reject("invalid_id", "id", "")
	}
	// 2. fountainID
	fid, _ := stringField(raw, "fountainID")
	if _, ok := cat.Get(fid); !ok {
		return d, reject("unknown_fountain", "fountainID", "")
	}
	d.FountainID = fid
	// 3. state (absent counts as unknown)
	d.State = "unknown"
	if v, present := present(raw, "state"); present {
		st, isString := stringOf(v)
		if !isString || !states[st] {
			return d, reject("invalid_state", "state", "")
		}
		d.State = st
	}
	// 4. rating
	if v, present := present(raw, "rating"); present {
		n, err := strconv.ParseInt(string(v), 10, 64)
		if err != nil || n < 1 || n > 5 {
			return d, reject("invalid_rating", "rating", "")
		}
		r := int(n)
		d.Rating = &r
	}
	// 5. something to say
	if d.State == "unknown" && d.Rating == nil {
		return d, reject("empty_report", "", "")
	}
	// 6. tags
	d.Tags = []string{}
	if v, present := present(raw, "tags"); present {
		var list []string
		if err := json.Unmarshal(v, &list); err != nil || len(list) > MaxTags {
			return d, reject("invalid_tags", "tags", "")
		}
		seen := map[string]bool{}
		for _, t := range list {
			if !tags[t] || seen[t] {
				return d, reject("invalid_tags", "tags", "")
			}
			seen[t] = true
		}
		d.Tags = list
	}
	// 7. note
	if v, present := present(raw, "note"); present {
		note, isString := stringOf(v)
		if !isString {
			return d, reject("invalid_note", "note", "control_characters")
		}
		note = strings.TrimSpace(note)
		if reason := checkNote(note); reason != "" {
			return d, reject("invalid_note", "note", reason)
		}
		d.Note = note
	}
	// 8. date
	ds, _ := stringField(raw, "date")
	date, err := httpx.ParseTime(ds)
	if err != nil || date.Before(now.Add(-PastWindow)) || date.After(now.Add(FutureWindow)) {
		return d, reject("invalid_date", "date", "")
	}
	d.Date = date
	return d, nil
}

func checkNote(note string) string {
	if utf8.RuneCountInString(note) > MaxNoteCodePoints {
		return "too_long"
	}
	for _, r := range note {
		if r == '\n' {
			continue
		}
		if unicode.IsControl(r) {
			return "control_characters"
		}
	}
	switch Check(note) {
	case Objectionable:
		return "objectionable"
	case ContainsContact:
		return "contains_contact"
	}
	return ""
}

// present returns a member's raw value unless it is absent or null.
func present(raw map[string]json.RawMessage, key string) (json.RawMessage, bool) {
	v, ok := raw[key]
	if !ok || string(bytes.TrimSpace(v)) == "null" {
		return nil, false
	}
	return v, true
}

func stringOf(v json.RawMessage) (string, bool) {
	var s string
	if err := json.Unmarshal(v, &s); err != nil {
		return "", false
	}
	return s, true
}

func stringField(raw map[string]json.RawMessage, key string) (string, bool) {
	v, ok := present(raw, key)
	if !ok {
		return "", false
	}
	return stringOf(v)
}

// Record builds the record to store from a draft.
func (d Draft) Record(author, installHash string, now time.Time) store.Record {
	return store.Record{
		ID: d.ID, FountainID: d.FountainID, State: d.State, Rating: d.Rating,
		Tags: d.Tags, Note: d.Note, Date: d.Date, CreatedAt: now.UTC().Truncate(time.Second),
		Author: author, InstallHash: installHash,
	}
}

// View is a report on the wire (api.md section 6.2). Rating is omitted when
// there is none, tags and note are always present and isMine is always false.
type View struct {
	ID         string   `json:"id"`
	FountainID string   `json:"fountainID"`
	State      string   `json:"state"`
	Rating     *int     `json:"rating,omitempty"`
	Tags       []string `json:"tags"`
	Note       string   `json:"note"`
	Date       string   `json:"date"`
	Author     string   `json:"author"`
	IsMine     bool     `json:"isMine"`
}

// ViewOf renders a stored record.
func ViewOf(r store.Record) View {
	tags := r.Tags
	if tags == nil {
		tags = []string{}
	}
	return View{
		ID: r.ID, FountainID: r.FountainID, State: r.State, Rating: r.Rating, Tags: tags,
		Note: r.Note, Date: httpx.FormatTime(r.Date), Author: r.Author,
	}
}

// Views renders a list; the result is never nil so it encodes as [].
func Views(rs []store.Record) []View {
	out := make([]View, len(rs))
	for i, r := range rs {
		out[i] = ViewOf(r)
	}
	return out
}
