package api

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/pedro-santiago/toret/backend/internal/store"
)

// seed puts n visible reports straight into the store, one a minute apart,
// newest last, all about the same fountain.
func seed(e *env, n int, fountainID string) {
	for i := 0; i < n; i++ {
		e.mem.PutReport(context.Background(), store.Record{
			ID: uuid(1000 + i), FountainID: fountainID, State: "running", Tags: []string{},
			Date: epoch.Add(-time.Duration(n-i) * time.Minute), Author: "Visitante 000000", InstallHash: "x",
		})
	}
}

func TestListLimits(t *testing.T) {
	e := newEnv(t)
	seed(e, 250, fountain)
	for _, tc := range []struct {
		path  string
		query map[string]string
		want  int
	}{
		{"/v1/reports", nil, 50},
		{"/v1/reports", map[string]string{"limit": "7"}, 7},
		{"/v1/reports", map[string]string{"limit": "200"}, 200},
		{"/v1/reports", map[string]string{"limit": "201"}, 200},
		{"/v1/reports", map[string]string{"limit": "100000"}, 200},
		{"/v1/reports", map[string]string{"limit": "99999999999999999999"}, 200},
		{"/v1/fountains/" + fountain + "/reports", nil, 40},
		{"/v1/fountains/" + fountain + "/reports", map[string]string{"limit": "100"}, 100},
		{"/v1/fountains/" + fountain + "/reports", map[string]string{"limit": "101"}, 100},
		{"/v1/fountains/422640291/reports", nil, 0},
	} {
		r := e.get(tc.path, tc.query, nil)
		if got := len(ids(t, r)); r.StatusCode != 200 || got != tc.want {
			t.Errorf("%s %v: %d reports (status %d), want %d", tc.path, tc.query, got, r.StatusCode, tc.want)
		}
	}
	// The maxima are not below what the app asks for (200 and 40), or merge
	// would mistake a short page for a complete download.
	for _, bad := range []string{"0", "-1", "abc", "", "1.5", "+5", " 5", "5 "} {
		r := e.get("/v1/reports", map[string]string{"limit": bad}, nil)
		if p := errOf(t, r); r.StatusCode != 400 || p.code != "invalid_limit" {
			t.Errorf("limit=%q: %d %+v", bad, r.StatusCode, p)
		}
	}
	if r := e.get("/v1/fountains/"+fountain+"/reports", map[string]string{"limit": "0"}, nil); r.StatusCode != 400 {
		t.Errorf("fountain limit=0: %d", r.StatusCode)
	}
}

func TestListOrderAndWindow(t *testing.T) {
	e := newEnv(t)
	put := func(id, fid string, age time.Duration) {
		e.mem.PutReport(context.Background(), store.Record{ID: id, FountainID: fid, State: "running", Date: epoch.Add(-age), Author: "Visitante 000000", InstallHash: "x"})
	}
	put("A", fountain, 3*time.Hour)
	put("B", fountain, time.Hour)
	put("C", fountain, time.Hour) // same second: the larger id first
	put("D", "422640291", 2*time.Hour)
	put("OLD", fountain, 30*24*time.Hour)              // exactly 30 days: inside (cutoff key is "T#")
	put("GONE", fountain, 30*24*time.Hour+time.Second) // a second older: outside
	put("ANCIENT", fountain, 45*24*time.Hour)

	if got := ids(t, e.get("/v1/reports", nil, nil)); fmt.Sprint(got) != "[C B D A OLD]" {
		t.Errorf("feed = %v", got)
	}
	if got := ids(t, e.get("/v1/fountains/"+fountain+"/reports", nil, nil)); fmt.Sprint(got) != "[C B A OLD]" {
		t.Errorf("fountain = %v", got)
	}
	// A second later OLD has aged out; TTL deletes lazily but reads never rely on it.
	e.now = e.now.Add(time.Second)
	if got := ids(t, e.get("/v1/reports", nil, nil)); fmt.Sprint(got) != "[C B D A]" {
		t.Errorf("feed one second later = %v", got)
	}
}

func TestFountainRoute(t *testing.T) {
	e := newEnv(t)
	if r := e.get("/v1/fountains/999/reports", nil, nil); r.StatusCode != 404 || errOf(t, r).code != "unknown_fountain" {
		t.Errorf("unknown: %d %s", r.StatusCode, r.Body)
	}
	for _, bad := range []string{"abc", "1234567890123", "42 1", "4213-10659"} {
		if r := e.get("/v1/fountains/"+strings.ReplaceAll(bad, " ", "%20")+"/reports", nil, nil); r.StatusCode != 400 {
			t.Errorf("id %q: %d", bad, r.StatusCode)
		}
	}
	r := e.get("/v1/fountains/422640291/reports", nil, nil)
	if r.StatusCode != 200 || r.Body != `{"reports":[]}` {
		t.Errorf("empty fountain: %d %s", r.StatusCode, r.Body)
	}
	if r := e.get("/v1/reports", nil, nil); r.Body != `{"reports":[]}` {
		t.Errorf("empty feed: %s", r.Body)
	}
}

func TestListHeadersAndETag(t *testing.T) {
	e := newEnv(t)
	e.submit(nil)
	r := e.get("/v1/reports", nil, nil)
	etag := r.Headers["ETag"]
	if len(etag) != 18 || etag[0] != '"' || etag[17] != '"' {
		t.Fatalf("etag = %q", etag)
	}
	if r.Headers["Cache-Control"] != "no-cache" || r.Headers["Vary"] != "Accept-Encoding" || r.Headers["Content-Type"] != "application/json; charset=utf-8" {
		t.Errorf("headers = %v", r.Headers)
	}
	// The same state gives the same ETag, with no generation time in the body.
	e.now = e.now.Add(5 * time.Minute)
	if again := e.get("/v1/reports", nil, nil); again.Headers["ETag"] != etag {
		t.Error("the etag changed without the data changing")
	}
	// The same ETag is shared by every client: it ignores the install header.
	if with := e.get("/v1/reports", nil, map[string]string{"X-Toret-Install": token(5)}); with.Headers["ETag"] != etag {
		t.Error("the install header changed the etag")
	}

	for _, inm := range []string{etag, "W/" + etag, `"nope", ` + etag, "*"} {
		n := e.get("/v1/reports", nil, map[string]string{"If-None-Match": inm})
		if n.StatusCode != 304 || n.Body != "" || n.Headers["ETag"] != etag || n.Headers["Cache-Control"] != "no-cache" {
			t.Errorf("If-None-Match %q: %d %q %v", inm, n.StatusCode, n.Body, n.Headers)
		}
		if _, has := n.Headers["Content-Type"]; has {
			t.Errorf("a 304 has no body to type: %v", n.Headers)
		}
	}
	for _, inm := range []string{`"0000000000000000"`, `W/"0000000000000000"`, ""} {
		if n := e.get("/v1/reports", nil, map[string]string{"If-None-Match": inm}); n.StatusCode != 200 || n.Headers["ETag"] != etag {
			t.Errorf("If-None-Match %q: %d", inm, n.StatusCode)
		}
	}
	// A new report changes the validator, so the old one gets a 200.
	e.submit(map[string]any{"fountainID": "422640291"})
	n := e.get("/v1/reports", nil, map[string]string{"If-None-Match": etag})
	if n.StatusCode != 200 || n.Headers["ETag"] == etag {
		t.Errorf("after a new report: %d %v", n.StatusCode, n.Headers["ETag"])
	}
	// The fountain list has its own validator.
	f := e.get("/v1/fountains/"+fountain+"/reports", nil, nil)
	if f.Headers["ETag"] == "" || e.get("/v1/fountains/"+fountain+"/reports", nil, map[string]string{"if-none-match": f.Headers["ETag"]}).StatusCode != 304 {
		t.Error("fountain list etag")
	}
}

func TestTimestampsHaveNoFractions(t *testing.T) {
	e := newEnv(t)
	e.now = epoch.Add(123 * time.Millisecond)
	e.submit(map[string]any{"date": epoch.Add(-time.Minute).Format(time.RFC3339Nano)})
	b := e.get("/v1/reports", nil, nil).Body
	if strings.Contains(b, ".") && strings.Contains(b, "Z") && strings.Contains(strings.SplitN(b, `"date":"`, 2)[1][:25], ".") {
		t.Errorf("fractional seconds on the wire: %s", b)
	}
	if !strings.Contains(b, `"date":"2026-10-12T11:59:00Z"`) {
		t.Errorf("date = %s", b)
	}
}

func TestGzip(t *testing.T) {
	e := newEnv(t)
	seed(e, 60, fountain)
	plainResp := e.get("/v1/reports", map[string]string{"limit": "60"}, nil)
	if plainResp.IsBase64Encoded || plainResp.Headers["Content-Encoding"] != "" || len(plainResp.Body) < 1024 {
		t.Fatalf("uncompressed: %v %d bytes", plainResp.Headers, len(plainResp.Body))
	}
	z := e.get("/v1/reports", map[string]string{"limit": "60"}, map[string]string{"Accept-Encoding": "br, gzip;q=0.8"})
	if !z.IsBase64Encoded || z.Headers["Content-Encoding"] != "gzip" || z.Headers["Vary"] != "Accept-Encoding" {
		t.Fatalf("compressed: %v", z.Headers)
	}
	if string(plain(t, z)) != plainResp.Body {
		t.Error("gzip body differs from the plain body")
	}
	if z.Headers["ETag"] != plainResp.Headers["ETag"] {
		t.Error("the etag is computed on the uncompressed body")
	}
	// gzip refused, small bodies and 304s are never compressed.
	if r := e.get("/v1/reports", map[string]string{"limit": "60"}, map[string]string{"Accept-Encoding": "gzip;q=0"}); r.IsBase64Encoded {
		t.Error("gzip;q=0 must not be compressed")
	}
	if r := e.get("/v1/reports", map[string]string{"limit": "3"}, map[string]string{"Accept-Encoding": "gzip"}); r.IsBase64Encoded {
		t.Error("a small body must not be compressed")
	}
	if r := e.get("/v1/reports", map[string]string{"limit": "60"}, map[string]string{"Accept-Encoding": "gzip", "If-None-Match": z.Headers["ETag"]}); r.StatusCode != 304 || r.Body != "" || r.IsBase64Encoded {
		t.Errorf("304: %d %q", r.StatusCode, r.Body)
	}
}

func TestSummariesFreshnessBoundary(t *testing.T) {
	e := newEnv(t)
	put := func(id, fid, state string, rating int, age time.Duration) {
		r := store.Record{ID: id, FountainID: fid, State: state, Date: epoch.Add(-age), Author: "Visitante 000000", InstallHash: "x"}
		if rating > 0 {
			r.Rating = &rating
		}
		e.mem.PutReport(context.Background(), r)
	}
	put("A", "421310659", "running", 5, time.Hour)
	put("B", "421310659", "unknown", 4, 30*time.Minute)
	put("C", "422640291", "dry", 0, 36*time.Hour)                 // exactly 36 h: inside, fresh
	put("D", "422640299", "running", 0, 36*time.Hour+time.Second) // outside the window
	r := e.get("/v1/summaries", nil, nil)
	if r.Headers["Cache-Control"] != "private, max-age=60" || r.Headers["ETag"] == "" || r.StatusCode != 200 {
		t.Fatalf("headers: %d %v", r.StatusCode, r.Headers)
	}
	want := `{"summaries":{"421310659":{"state":"running","latestDate":"2026-10-12T11:00:00Z","average":4.5,"ratingCount":2,"reportCount":2},` +
		`"422640291":{"state":"dry","latestDate":"2026-10-11T00:00:00Z","ratingCount":0,"reportCount":1}},"windowHours":36}`
	if r.Body != want {
		t.Errorf("summaries\n got %s\nwant %s", r.Body, want)
	}
	if n := e.get("/v1/summaries", nil, map[string]string{"If-None-Match": r.Headers["ETag"]}); n.StatusCode != 304 {
		t.Errorf("etag: %d", n.StatusCode)
	}
}

func TestSummariesAreCachedForTwentySeconds(t *testing.T) {
	e := newEnv(t)
	e.submit(nil)
	first := e.get("/v1/summaries", nil, nil).Body
	e.submit(map[string]any{"fountainID": "422640291"})
	e.now = e.now.Add(19 * time.Second)
	if e.get("/v1/summaries", nil, nil).Body != first {
		t.Error("summaries recomputed within 20 s")
	}
	feeds := e.mem.Calls["Feed"]
	e.now = e.now.Add(time.Second)
	if e.get("/v1/summaries", nil, nil).Body == first || e.mem.Calls["Feed"] != feeds+1 {
		t.Error("summaries not recomputed after 20 s")
	}
	// The clock going backwards (a new warm container) never serves a stale body.
	e.now = e.now.Add(-time.Hour)
	if e.get("/v1/summaries", nil, nil); e.mem.Calls["Feed"] != feeds+2 {
		t.Error("clock skew must refresh")
	}
}

func TestSummariesEmpty(t *testing.T) {
	e := newEnv(t)
	if r := e.get("/v1/summaries", nil, nil); r.Body != `{"summaries":{},"windowHours":36}` {
		t.Errorf("empty = %s", r.Body)
	}
}
