package reports

import (
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/pedro-santiago/toret/backend/internal/catalogue"
)

var now = time.Date(2026, 10, 12, 12, 0, 0, 0, time.UTC)

func cat(t *testing.T) *catalogue.Catalogue {
	t.Helper()
	c, err := catalogue.Embedded()
	if err != nil {
		t.Fatal(err)
	}
	return c
}

// body builds a valid report body and lets a case change one member.
func body(t *testing.T, edit map[string]any) []byte {
	t.Helper()
	m := map[string]any{
		"id": "7d2b7c54-3f0a-4c5e-8b6d-0e5c6c1b9a10", "fountainID": "421310659", "state": "running",
		"rating": 5, "tags": []string{"cold", "clean"}, "note": "Água gelada, sem fila.",
		"date": "2026-10-12T11:41:00Z",
	}
	for k, v := range edit {
		if v == nil {
			delete(m, k)
		} else {
			m[k] = v
		}
	}
	b, err := json.Marshal(m)
	if err != nil {
		t.Fatal(err)
	}
	return b
}

type null struct{} // marshals as JSON null

func (null) MarshalJSON() ([]byte, error) { return []byte("null"), nil }

func TestValidateAccepts(t *testing.T) {
	c := cat(t)
	d, rej := Validate(body(t, nil), c, now)
	if rej != nil {
		t.Fatalf("rejected: %+v", rej)
	}
	if d.ID != "7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10" || d.State != "running" || *d.Rating != 5 || len(d.Tags) != 2 || d.Note != "Água gelada, sem fila." {
		t.Errorf("draft = %+v", d)
	}

	// Rating alone, state alone, null members, author and isMine ignored,
	// fractions and offsets in the date normalised, note trimmed.
	for name, edit := range map[string]map[string]any{
		"rating only":       {"state": "unknown", "rating": 3},
		"state absent":      {"state": nil, "rating": 3},
		"state only":        {"rating": nil, "state": "dry"},
		"null rating":       {"rating": null{}, "state": "weak"},
		"null tags":         {"tags": null{}},
		"null note":         {"note": null{}},
		"no tags":           {"tags": nil},
		"author ignored":    {"author": "Visitante 000000", "isMine": true, "extra": 1},
		"fraction":          {"date": "2026-10-12T11:41:00.789Z"},
		"offset":            {"date": "2026-10-12T13:41:00+02:00"},
		"trimmed note":      {"note": "  \n ok \n"},
		"280 code points":   {"note": strings.Repeat("a", 280)},
		"emoji count":       {"note": strings.Repeat("👍🏽", 140)},
		"three tags":        {"tags": []string{"cold", "clean", "shade"}},
		"newline in note":   {"note": "linha 1\nlinha 2"},
		"30 days back":      {"date": "2026-09-12T12:00:00Z"},
		"10 minutes ahead":  {"date": "2026-10-12T12:10:00Z"},
		"unknown catalogue": {"fountainID": "422640291"},
	} {
		if _, rej := Validate(body(t, edit), c, now); rej != nil {
			t.Errorf("%s: rejected %+v", name, rej)
		}
	}

	d, _ = Validate(body(t, map[string]any{"date": "2026-10-12T13:41:00.9+02:00", "note": "  \n ok \n"}), c, now)
	if got := d.Date.Format(time.RFC3339Nano); got != "2026-10-12T11:41:00Z" || d.Note != "ok" {
		t.Errorf("normalisation: date %s, note %q", got, d.Note)
	}
}

func TestValidateRejects(t *testing.T) {
	c := cat(t)
	for _, tc := range []struct {
		name   string
		body   []byte
		status int
		code   string
		field  string
		reason string
	}{
		{"not json", []byte(`{"id":`), 400, "bad_request", "", ""},
		{"empty body", nil, 400, "bad_request", "", ""},
		{"array", []byte(`[]`), 400, "bad_request", "", ""},
		{"null", []byte(`null`), 400, "bad_request", "", ""},
		{"two objects", []byte(`{} {}`), 400, "bad_request", "", ""},
		{"trailing brace", append(body(t, nil), '}'), 400, "bad_request", "", ""},

		{"id missing", body(t, map[string]any{"id": nil}), 422, "invalid_id", "id", ""},
		{"id not uuid", body(t, map[string]any{"id": "123"}), 422, "invalid_id", "id", ""},
		{"id number", body(t, map[string]any{"id": 5}), 422, "invalid_id", "id", ""},
		{"fountain missing", body(t, map[string]any{"fountainID": nil}), 422, "unknown_fountain", "fountainID", ""},
		{"fountain unknown", body(t, map[string]any{"fountainID": "1"}), 422, "unknown_fountain", "fountainID", ""},
		{"fountain number", body(t, map[string]any{"fountainID": 421310659}), 422, "unknown_fountain", "fountainID", ""},
		{"state unknown value", body(t, map[string]any{"state": "flowing"}), 422, "invalid_state", "state", ""},
		{"state empty", body(t, map[string]any{"state": ""}), 422, "invalid_state", "state", ""},
		{"state number", body(t, map[string]any{"state": 1}), 422, "invalid_state", "state", ""},
		{"state case", body(t, map[string]any{"state": "Running"}), 422, "invalid_state", "state", ""},
		{"rating 0", body(t, map[string]any{"rating": 0}), 422, "invalid_rating", "rating", ""},
		{"rating 6", body(t, map[string]any{"rating": 6}), 422, "invalid_rating", "rating", ""},
		{"rating -1", body(t, map[string]any{"rating": -1}), 422, "invalid_rating", "rating", ""},
		{"rating fraction", body(t, map[string]any{"rating": 4.5}), 422, "invalid_rating", "rating", ""},
		{"rating string", body(t, map[string]any{"rating": "5"}), 422, "invalid_rating", "rating", ""},
		{"empty report", body(t, map[string]any{"state": "unknown", "rating": nil}), 422, "empty_report", "", ""},
		{"empty report no state", body(t, map[string]any{"state": nil, "rating": nil}), 422, "empty_report", "", ""},
		{"four tags", body(t, map[string]any{"tags": []string{"cold", "clean", "shade", "dirty"}}), 422, "invalid_tags", "tags", ""},
		{"duplicate tag", body(t, map[string]any{"tags": []string{"cold", "cold"}}), 422, "invalid_tags", "tags", ""},
		{"unknown tag", body(t, map[string]any{"tags": []string{"wet"}}), 422, "invalid_tags", "tags", ""},
		{"tags not a list", body(t, map[string]any{"tags": "cold"}), 422, "invalid_tags", "tags", ""},
		{"note too long", body(t, map[string]any{"note": strings.Repeat("a", 281)}), 422, "invalid_note", "note", "too_long"},
		{"note control", body(t, map[string]any{"note": "a\x07b"}), 422, "invalid_note", "note", "control_characters"},
		{"note tab", body(t, map[string]any{"note": "a\tb"}), 422, "invalid_note", "note", "control_characters"},
		{"note carriage return", body(t, map[string]any{"note": "a\r\nb"}), 422, "invalid_note", "note", "control_characters"},
		{"note contact", body(t, map[string]any{"note": "Ligue 011 123 4567"}), 422, "invalid_note", "note", "contains_contact"},
		{"note objectionable", body(t, map[string]any{"note": "Fuck this"}), 422, "invalid_note", "note", "objectionable"},
		{"note number", body(t, map[string]any{"note": 5}), 422, "invalid_note", "note", "control_characters"},
		{"date missing", body(t, map[string]any{"date": nil}), 422, "invalid_date", "date", ""},
		{"date garbage", body(t, map[string]any{"date": "yesterday"}), 422, "invalid_date", "date", ""},
		{"date no zone", body(t, map[string]any{"date": "2026-10-12T11:41:00"}), 422, "invalid_date", "date", ""},
		{"date too old", body(t, map[string]any{"date": "2026-09-12T11:59:59Z"}), 422, "invalid_date", "date", ""},
		{"date too far ahead", body(t, map[string]any{"date": "2026-10-12T12:10:01Z"}), 422, "invalid_date", "date", ""},
	} {
		_, rej := Validate(tc.body, c, now)
		if rej == nil {
			t.Errorf("%s: accepted", tc.name)
			continue
		}
		if rej.Status != tc.status || rej.Code != tc.code || rej.Field != tc.field || rej.Reason != tc.reason {
			t.Errorf("%s: got %+v, want %d %s field=%q reason=%q", tc.name, *rej, tc.status, tc.code, tc.field, tc.reason)
		}
	}
}

// First failure wins, in the order of section 6.4.
func TestValidateOrder(t *testing.T) {
	c := cat(t)
	b := body(t, map[string]any{"id": "x", "fountainID": "1", "state": "nope", "rating": 9, "tags": 1, "note": "Fuck", "date": "x"})
	want := []string{"invalid_id", "unknown_fountain", "invalid_state", "invalid_rating", "invalid_tags", "invalid_note", "invalid_date"}
	m := map[string]json.RawMessage{}
	json.Unmarshal(b, &m)
	fixes := []func(){
		func() { m["id"] = json.RawMessage(`"7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10"`) },
		func() { m["fountainID"] = json.RawMessage(`"421310659"`) },
		func() { m["state"] = json.RawMessage(`"running"`) },
		func() { m["rating"] = json.RawMessage(`4`) },
		func() { m["tags"] = json.RawMessage(`[]`) },
		func() { m["note"] = json.RawMessage(`"ok"`) },
		func() { m["date"] = json.RawMessage(`"2026-10-12T11:41:00Z"`) },
	}
	for i, code := range want {
		raw, _ := json.Marshal(m)
		_, rej := Validate(raw, c, now)
		if rej == nil || rej.Code != code {
			t.Fatalf("step %d: got %+v, want %s", i, rej, code)
		}
		fixes[i]()
	}
	raw, _ := json.Marshal(m)
	if _, rej := Validate(raw, c, now); rej != nil {
		t.Errorf("all fixed: %+v", rej)
	}
}

func TestViewShape(t *testing.T) {
	d, _ := Validate(body(t, map[string]any{"rating": nil, "tags": nil, "note": nil}), cat(t), now)
	rec := d.Record("Visitante E95596", "hash", now)
	rec.Tags = nil
	got, _ := json.Marshal(ViewOf(rec))
	want := `{"id":"7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10","fountainID":"421310659","state":"running","tags":[],"note":"","date":"2026-10-12T11:41:00Z","author":"Visitante E95596","isMine":false}`
	if string(got) != want {
		t.Errorf("got  %s\nwant %s", got, want)
	}
	if b, _ := json.Marshal(Views(nil)); string(b) != "[]" {
		t.Errorf("Views(nil) = %s", b)
	}
}

func TestNormaliseID(t *testing.T) {
	if id, ok := NormaliseID("7d2b7c54-3f0a-4c5e-8b6d-0e5c6c1b9a10"); !ok || id != "7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10" {
		t.Errorf("got %q %v", id, ok)
	}
	for _, bad := range []string{"", "7d2b7c543f0a4c5e8b6d0e5c6c1b9a10", "7d2b7c54-3f0a-4c5e-8b6d-0e5c6c1b9a1g", "7d2b7c54-3f0a-4c5e-8b6d-0e5c6c1b9a10 "} {
		if _, ok := NormaliseID(bad); ok {
			t.Errorf("accepted %q", bad)
		}
	}
}

// The tolerance for a fast clock never lets a report be dated after "now".
func TestFutureDateIsClampedToNow(t *testing.T) {
	c := cat(t)
	at := now.Add(250 * time.Millisecond) // whole seconds in the record
	for _, tc := range []struct {
		date string
		want time.Time
	}{
		{"2026-10-12T12:09:59Z", now},                   // inside the 10 minutes: now
		{"2026-10-12T14:09:59+02:00", now},              // the same, in another zone
		{"2026-10-12T12:00:00Z", now},                   // exactly now
		{"2026-10-12T11:59:59Z", now.Add(-time.Second)}, // past: untouched
	} {
		d, rej := Validate(body(t, map[string]any{"date": tc.date}), c, at)
		if rej != nil || !d.Date.Equal(tc.want) || d.Date.Nanosecond() != 0 {
			t.Errorf("date %s: %v, %v; want %v", tc.date, d.Date, rej, tc.want)
		}
	}
	if _, rej := Validate(body(t, map[string]any{"date": "2026-10-12T12:10:01Z"}), c, now); rej == nil || rej.Code != "invalid_date" {
		t.Errorf("more than 10 minutes ahead: %+v", rej)
	}
}
