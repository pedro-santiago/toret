package httpx

import (
	"encoding/json"
	"testing"
	"time"
)

func TestFormatTime(t *testing.T) {
	loc := time.FixedZone("x", 2*3600)
	if got := FormatTime(time.Date(2026, 10, 12, 11, 41, 0, 789_000_000, loc)); got != "2026-10-12T09:41:00Z" {
		t.Errorf("got %s", got)
	}
	for in, want := range map[string]string{
		"2026-10-12T09:41:00Z":        "2026-10-12T09:41:00Z",
		"2026-10-12T09:41:00.987Z":    "2026-10-12T09:41:00Z",
		"2026-10-12T11:41:00+02:00":   "2026-10-12T09:41:00Z",
		"2026-10-12T11:41:00.5-03:00": "2026-10-12T14:41:00Z",
	} {
		got, err := ParseTime(in)
		if err != nil || FormatTime(got) != want {
			t.Errorf("ParseTime(%q) = %v, %v", in, got, err)
		}
	}
	for _, bad := range []string{"", "2026-10-12", "2026-10-12T09:41:00", "12/10/2026"} {
		if _, err := ParseTime(bad); err == nil {
			t.Errorf("ParseTime(%q) accepted", bad)
		}
	}
}

func TestMatches(t *testing.T) {
	const tag = `"0123456789abcdef"`
	for _, tc := range []struct {
		header string
		want   bool
	}{
		{tag, true}, {"W/" + tag, true}, {` "other" , ` + tag, true}, {"*", true},
		{`"other"`, false}, {"", false}, {`0123456789abcdef`, false},
	} {
		if got := Matches(tc.header, tag); got != tc.want {
			t.Errorf("Matches(%q) = %v", tc.header, got)
		}
	}
}

func TestETagIsStrongAndShort(t *testing.T) {
	a, b := ETag([]byte(`{"a":1}`)), ETag([]byte(`{"a":2}`))
	if a == b || len(a) != 18 || a != ETag([]byte(`{"a":1}`)) {
		t.Errorf("etags: %s %s", a, b)
	}
}

func TestAcceptsGzip(t *testing.T) {
	for in, want := range map[string]bool{
		"gzip": true, "br, gzip": true, "gzip;q=0.5": true, "GZIP": true, "*": true,
		"gzip;q=0": false, "gzip; q=0": false, "br": false, "identity": false, "": false,
	} {
		if got := AcceptsGzip(in); got != want {
			t.Errorf("AcceptsGzip(%q) = %v", in, got)
		}
	}
}

func TestLang(t *testing.T) {
	for in, want := range map[string]string{
		"": "en", "pt-BR,pt;q=0.9,en;q=0.8": "pt", "it": "it", "en-GB": "en", "de-DE,de": "en", "fr, it;q=0.5": "it", "PT": "pt",
	} {
		if got := Lang(in); got != want {
			t.Errorf("Lang(%q) = %s", in, got)
		}
	}
}

func TestErrorBody(t *testing.T) {
	r := Finish(Fail(422, "invalid_note", "note", "contains_contact"), "rid-1", "pt", false)
	var got struct {
		Error map[string]string `json:"error"`
	}
	if err := json.Unmarshal([]byte(r.Body), &got); err != nil {
		t.Fatal(err)
	}
	if r.StatusCode != 422 || got.Error["code"] != "invalid_note" || got.Error["field"] != "note" || got.Error["reason"] != "contains_contact" ||
		got.Error["requestId"] != "rid-1" || got.Error["message"] == "" || r.Headers["X-Request-Id"] != "rid-1" {
		t.Errorf("%d %s %v", r.StatusCode, r.Body, r.Headers)
	}
	// Optional members are left out, and every code has a message in every language.
	r = Finish(Fail(401, "install_required", "", ""), "", "en", false)
	if want := `{"error":{"code":"install_required","message":"X-Toret-Install is missing or malformed."}}`; r.Body != want {
		t.Errorf("got %s", r.Body)
	}
	for key, m := range messages {
		for i, text := range m {
			if text == "" {
				t.Errorf("%s has no message in language %d", key, i)
			}
		}
	}
}
