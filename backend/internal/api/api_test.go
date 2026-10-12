package api

import (
	"context"
	"encoding/base64"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-lambda-go/events"

	"github.com/pedro-santiago/toret/backend/internal/ratelimit"
	"github.com/pedro-santiago/toret/backend/internal/store"
)

func TestHealth(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.Pepper = func(context.Context) ([]byte, error) { return nil, errBoom } })
	r := e.get("/v1/health", nil, nil)
	m := decode(t, r)
	if r.StatusCode != 200 || m["status"] != "ok" || m["version"] != "1.0.0" || m["catalogue"] != float64(723) {
		t.Errorf("health = %d %s", r.StatusCode, r.Body)
	}
	if r.Headers["Cache-Control"] != "no-store" || r.Headers["Content-Type"] != "application/json; charset=utf-8" {
		t.Errorf("headers = %v", r.Headers)
	}
	if len(e.mem.Calls) != 0 {
		t.Errorf("health touched the store: %v", e.mem.Calls)
	}
}

func TestCreateReport(t *testing.T) {
	e := newEnv(t)
	tok := "5B0C6E0D-7F7B-4D5E-9E3A-2C1F8A4B9D10"
	id := "7d2b7c54-3f0a-4c5e-8b6d-0e5c6c1b9a10" // lower case in, upper case out
	r := e.post(tok, payload(id, map[string]any{
		"author": "Visitante 000000", "isMine": true, "note": "  Água gelada, sem fila.\n",
		"date": epoch.Add(-19 * time.Minute).Format(time.RFC3339Nano),
	}))
	if r.StatusCode != 201 {
		t.Fatalf("status %d: %s", r.StatusCode, r.Body)
	}
	want := `{"id":"7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10","fountainID":"421310659","state":"running","rating":5,"tags":["cold","clean"],"note":"Água gelada, sem fila.","date":"2026-10-12T11:41:00Z","author":"Visitante E95596","isMine":false}`
	if r.Body != want {
		t.Errorf("body\n got %s\nwant %s", r.Body, want)
	}
	for k, v := range map[string]string{
		"Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store", "X-Request-Id": "req-0",
		"RateLimit-Limit": "1000", "RateLimit-Remaining": "999", "RateLimit-Reset": "3600",
	} {
		if r.Headers[k] != v {
			t.Errorf("header %s = %q, want %q", k, r.Headers[k], v)
		}
	}

	// What is stored: the handle and a hash, never the token; the TTL is the
	// report's date plus 30 days.
	rec := e.mem.Stored("7D2B7C54-3F0A-4C5E-8B6D-0E5C6C1B9A10")
	if rec == nil || rec.Author != "Visitante E95596" || rec.InstallHash != "875c150fd8da0ca82b126a92d07c18a2bc896a13546db56f1175764871d48911" {
		t.Fatalf("stored = %+v", rec)
	}
	if !rec.CreatedAt.Equal(epoch) {
		t.Errorf("createdAt = %s", rec.CreatedAt)
	}
	if strings.Contains(fmt.Sprintf("%+v", rec), tok) {
		t.Error("the raw token reached the store")
	}
	// ...nor the logs.
	if s := e.logs.String(); strings.Contains(s, tok) || strings.Contains(s, "203.0.113.7") {
		t.Errorf("logs leak the token or the address: %s", s)
	}
	if !strings.Contains(e.logs.String(), `"client":"1.0.0+42"`) {
		t.Errorf("client header not logged: %s", e.logs.String())
	}
}

func TestCreateWithoutRatingOrTags(t *testing.T) {
	e := newEnv(t)
	_, _, r := e.submit(map[string]any{"rating": nil, "tags": nil, "note": nil})
	if !strings.Contains(r.Body, `"tags":[],"note":"",`) || strings.Contains(r.Body, "rating") {
		t.Errorf("body = %s", r.Body)
	}
}

func TestIdempotency(t *testing.T) {
	e := newEnv(t)
	id, tok, first := e.submit(nil)

	// Same id, same install: the stored report, whatever the body says now, and
	// no counter is consumed.
	before := e.mem.Counter("RL#INSTALL#" + hashOf(tok) + "#" + fmt.Sprint(e.now.Unix()/3600))
	for i := 0; i < 3; i++ {
		r := e.post(tok, payload(id, map[string]any{"state": "dry", "rating": 1, "note": "mudou"}))
		if r.StatusCode != 200 || r.Body != first.Body {
			t.Fatalf("retry %d: %d %s", i, r.StatusCode, r.Body)
		}
	}
	if after := e.mem.Counter("RL#INSTALL#" + hashOf(tok) + "#" + fmt.Sprint(e.now.Unix()/3600)); after != before {
		t.Errorf("retries consumed the rate limit: %d -> %d", before, after)
	}
	if len(ids(t, e.get("/v1/reports", nil, nil))) != 1 {
		t.Error("a retry created a second report")
	}

	// Another install cannot take the id over.
	r := e.post(token(999), payload(id, nil))
	if r.StatusCode != 409 || errOf(t, r).code != "id_conflict" {
		t.Errorf("other install: %d %s", r.StatusCode, r.Body)
	}
	// ...not even with a differently cased id.
	r = e.post(token(999), payload(strings.ToLower(id), nil))
	if r.StatusCode != 409 {
		t.Errorf("lower-cased id: %d", r.StatusCode)
	}
}

// A retry is a success even when the install is at its limit.
func TestIdempotentRetryBeatsRateLimit(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.Limits = ratelimit.Config{InstallPerHour: 1, IPPerHour: 100} })
	id, tok := uuid(1), token(1)
	if r := e.post(tok, payload(id, nil)); r.StatusCode != 201 {
		t.Fatal(r.Body)
	}
	if r := e.post(tok, payload(id, nil)); r.StatusCode != 200 {
		t.Errorf("retry at the limit: %d %s", r.StatusCode, r.Body)
	}
	if r := e.post(tok, payload(uuid(2), map[string]any{"fountainID": "422640291"})); r.StatusCode != 429 {
		t.Errorf("a new report at the limit: %d", r.StatusCode)
	}
}

func TestLostRace(t *testing.T) {
	// The first GetReport sees nothing, then a concurrent request wins the put.
	e := newEnv(t)
	tok := token(1)
	racer := &racingStore{Memory: e.mem, onPut: func() {
		e.mem.PutReport(context.Background(), store.Record{
			ID: uuid(1), FountainID: fountain, State: "running", Date: epoch, Author: authorOf(tok), InstallHash: hashOf(tok),
		})
	}}
	e.h.cfg.Store = racer
	e.h.limiter.Counter = racer
	r := e.post(tok, payload(uuid(1), nil))
	if r.StatusCode != 200 {
		t.Errorf("same install lost the race: %d %s", r.StatusCode, r.Body)
	}
	e2 := newEnv(t)
	racer2 := &racingStore{Memory: e2.mem, onPut: func() {
		e2.mem.PutReport(context.Background(), store.Record{ID: uuid(1), FountainID: fountain, State: "running", Date: epoch, InstallHash: "other"})
	}}
	e2.h.cfg.Store = racer2
	e2.h.limiter.Counter = racer2
	if r := e2.post(tok, payload(uuid(1), nil)); r.StatusCode != 409 {
		t.Errorf("another install won the race: %d %s", r.StatusCode, r.Body)
	}
}

type racingStore struct {
	*store.Memory
	onPut func()
}

func (r *racingStore) PutReport(ctx context.Context, rec store.Record) (bool, error) {
	r.onPut()
	return r.Memory.PutReport(ctx, rec)
}

func TestWriteChecksRunInOrder(t *testing.T) {
	e := newEnv(t)
	big := payload(uuid(1), map[string]any{"pad": strings.Repeat("x", 5000)})
	ok := payload(uuid(1), nil)
	good := jsonHeaders(token(1))
	for _, tc := range []struct {
		name    string
		headers map[string]string
		body    string
		status  int
		code    string
	}{
		{"too large beats content type", map[string]string{"X-Toret-Install": token(1)}, big, 413, "body_too_large"},
		{"too large beats install", map[string]string{"Content-Type": "application/json"}, big, 413, "body_too_large"},
		{"content type beats install", map[string]string{}, ok, 415, "unsupported_media_type"},
		{"text/plain", map[string]string{"Content-Type": "text/plain", "X-Toret-Install": token(1)}, ok, 415, "unsupported_media_type"},
		{"form", map[string]string{"Content-Type": "application/x-www-form-urlencoded", "X-Toret-Install": token(1)}, ok, 415, "unsupported_media_type"},
		{"install beats validation", map[string]string{"Content-Type": "application/json"}, "{}", 401, "install_required"},
		{"install too short", map[string]string{"Content-Type": "application/json", "X-Toret-Install": "short"}, ok, 401, "install_required"},
		{"install bad char", map[string]string{"Content-Type": "application/json", "X-Toret-Install": "install token with spaces"}, ok, 401, "install_required"},
		{"install too long", map[string]string{"Content-Type": "application/json", "X-Toret-Install": strings.Repeat("a", 65)}, ok, 401, "install_required"},
		{"upper-case media type", map[string]string{"Content-Type": "Application/JSON", "X-Toret-Install": token(1)}, ok, 201, ""},
		{"malformed json", good, `{"id":`, 400, "bad_request"},
		{"empty body", good, ``, 400, "bad_request"},
		{"not an object", good, `[1]`, 400, "bad_request"},
	} {
		r := e.do(call{method: "POST", path: "/v1/reports", headers: tc.headers, body: tc.body})
		if r.StatusCode != tc.status {
			t.Errorf("%s: status %d, want %d: %s", tc.name, r.StatusCode, tc.status, r.Body)
			continue
		}
		if tc.code != "" {
			p := errOf(t, r)
			if p.code != tc.code || p.requestID == "" || p.message == "" {
				t.Errorf("%s: error = %+v", tc.name, p)
			}
			if _, has := r.Headers["RateLimit-Limit"]; has {
				t.Errorf("%s: refused before the counters but sent RateLimit headers", tc.name)
			}
		}
	}
	if e.mem.Calls["Incr"] != 3 { // install, IP and fountain of the one accepted report
		t.Errorf("counters consulted %d times, want 3", e.mem.Calls["Incr"])
	}
}

func TestBodySizeBoundary(t *testing.T) {
	e := newEnv(t)
	pad := func(total int) string {
		b := payload(uuid(e.fresh()), map[string]any{"pad": ""})
		return payload(uuid(e.n), map[string]any{"pad": strings.Repeat("x", total-len(b))})
	}
	if b := pad(4096); len(b) != 4096 {
		t.Fatalf("helper: %d", len(b))
	} else if r := e.post(token(e.fresh()), b); r.StatusCode != 201 {
		t.Errorf("exactly 4 KiB: %d %s", r.StatusCode, r.Body)
	}
	if b := pad(4097); len(b) != 4097 {
		t.Fatalf("helper: %d", len(b))
	} else if r := e.post(token(e.fresh()), b); r.StatusCode != 413 {
		t.Errorf("4 KiB + 1: %d", r.StatusCode)
	}
	// Multibyte characters count as bytes.
	if r := e.post(token(e.fresh()), payload(uuid(e.fresh()), map[string]any{"pad": strings.Repeat("é", 2100)})); r.StatusCode != 413 {
		t.Errorf("4200 bytes of é: %d", r.StatusCode)
	}
}

func TestBase64Body(t *testing.T) {
	e := newEnv(t)
	b := payload(uuid(1), nil)
	r := e.do(call{method: "POST", path: "/v1/reports", headers: jsonHeaders(token(1)), body: base64.StdEncoding.EncodeToString([]byte(b)), b64: true})
	if r.StatusCode != 201 {
		t.Errorf("base64 body: %d %s", r.StatusCode, r.Body)
	}
	huge := base64.StdEncoding.EncodeToString([]byte(strings.Repeat("a", 4097)))
	if r := e.do(call{method: "POST", path: "/v1/reports", headers: jsonHeaders(token(2)), body: huge, b64: true}); r.StatusCode != 413 {
		t.Errorf("4097 decoded bytes: %d", r.StatusCode)
	}
	if r := e.do(call{method: "POST", path: "/v1/reports", headers: jsonHeaders(token(2)), body: "@@@", b64: true}); r.StatusCode != 400 {
		t.Errorf("invalid base64: %d", r.StatusCode)
	}
}

func TestValidationThroughHandler(t *testing.T) {
	e := newEnv(t)
	for _, tc := range []struct {
		name   string
		over   map[string]any
		status int
		code   string
		field  string
		reason string
	}{
		{"unknown fountain", map[string]any{"fountainID": "999"}, 422, "unknown_fountain", "fountainID", ""},
		{"bad id", map[string]any{"id": "nope"}, 422, "invalid_id", "id", ""},
		{"bad state", map[string]any{"state": "flowing"}, 422, "invalid_state", "state", ""},
		{"rating 0", map[string]any{"rating": 0}, 422, "invalid_rating", "rating", ""},
		{"empty report", map[string]any{"state": "unknown", "rating": nil}, 422, "empty_report", "", ""},
		{"five tags", map[string]any{"tags": []string{"cold", "clean", "shade", "dirty", "hardToFind"}}, 422, "invalid_tags", "tags", ""},
		{"contact", map[string]any{"note": "Ligue 011 123 4567"}, 422, "invalid_note", "note", "contains_contact"},
		{"objectionable", map[string]any{"note": "Fuck this"}, 422, "invalid_note", "note", "objectionable"},
		{"too long", map[string]any{"note": strings.Repeat("a", 281)}, 422, "invalid_note", "note", "too_long"},
		{"old date", map[string]any{"date": epoch.Add(-31 * 24 * time.Hour).Format(time.RFC3339)}, 422, "invalid_date", "date", ""},
		{"future date", map[string]any{"date": epoch.Add(11 * time.Minute).Format(time.RFC3339)}, 422, "invalid_date", "date", ""},
	} {
		r := e.post(token(e.fresh()), payload(uuid(e.n), tc.over))
		if r.StatusCode != tc.status {
			t.Errorf("%s: %d %s", tc.name, r.StatusCode, r.Body)
			continue
		}
		if p := errOf(t, r); p.code != tc.code || p.field != tc.field || p.reason != tc.reason {
			t.Errorf("%s: %+v", tc.name, p)
		}
	}
	if e.mem.Calls["PutReport"] != 0 || e.mem.Calls["Incr"] != 0 {
		t.Errorf("a rejected report reached the store: %v", e.mem.Calls)
	}
}

func TestErrorMessagesFollowAcceptLanguage(t *testing.T) {
	e := newEnv(t)
	seen := map[string]bool{}
	for _, lang := range []string{"", "en-US,en;q=0.9", "pt-BR,pt;q=0.9", "it-IT", "de"} {
		r := e.do(call{method: "POST", path: "/v1/reports", headers: map[string]string{
			"Content-Type": "application/json", "X-Toret-Install": token(1), "Accept-Language": lang,
		}, body: payload(uuid(1), map[string]any{"note": "Ligue 011 123 4567"})})
		m := errOf(t, r).message
		seen[m] = true
		switch lang {
		case "pt-BR,pt;q=0.9":
			if !strings.Contains(m, "telefone") {
				t.Errorf("pt message = %q", m)
			}
		case "it-IT":
			if !strings.Contains(m, "telefono") {
				t.Errorf("it message = %q", m)
			}
		default:
			if !strings.Contains(m, "phone number") {
				t.Errorf("%q message = %q", lang, m)
			}
		}
	}
	if len(seen) != 3 {
		t.Errorf("%d distinct messages, want 3", len(seen))
	}
}

func TestBan(t *testing.T) {
	e := newEnv(t)
	e.mem.Ban(hashOf(token(1)))
	if r := e.post(token(1), payload(uuid(1), nil)); r.StatusCode != 403 || errOf(t, r).code != "forbidden" {
		t.Errorf("banned post: %d %s", r.StatusCode, r.Body)
	}
	if r := e.delete(token(1), uuid(1)); r.StatusCode != 403 {
		t.Errorf("banned delete: %d", r.StatusCode)
	}
	if r := e.flag(token(1), uuid(1), "", `{"reason":"spam"}`); r.StatusCode != 403 {
		t.Errorf("banned flag: %d", r.StatusCode)
	}
	if e.mem.Calls["Incr"] != 0 {
		t.Error("a banned install consumed counters")
	}
	// Reads are open to everyone.
	if r := e.get("/v1/reports", nil, nil); r.StatusCode != 200 {
		t.Errorf("read: %d", r.StatusCode)
	}
}

func TestRateLimits(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.Limits = ratelimit.Config{InstallPerHour: 3, IPPerHour: 5} })
	tok := token(1)
	fountains := []string{"421310659", "422640291", "422640299", "422640314"}
	for i := 0; i < 3; i++ {
		r := e.post(tok, payload(uuid(i+1), map[string]any{"fountainID": fountains[i]}))
		if r.StatusCode != 201 {
			t.Fatalf("report %d: %d %s", i, r.StatusCode, r.Body)
		}
		if r.Headers["RateLimit-Remaining"] != fmt.Sprint(2-i) || r.Headers["RateLimit-Limit"] != "3" {
			t.Errorf("report %d headers: %v", i, r.Headers)
		}
	}
	r := e.post(tok, payload(uuid(4), map[string]any{"fountainID": fountains[3]}))
	p := errOf(t, r)
	if r.StatusCode != 429 || p.code != "rate_limited" || p.reason != "install" || r.Headers["Retry-After"] != "3600" ||
		r.Headers["RateLimit-Remaining"] != "0" || r.Headers["RateLimit-Reset"] != "3600" {
		t.Errorf("4th report: %d %v %+v", r.StatusCode, r.Headers, p)
	}
	// Deletes and flags share the install bucket.
	if r := e.delete(tok, uuid(1)); r.StatusCode != 429 {
		t.Errorf("delete over the limit: %d", r.StatusCode)
	}
	if r := e.flag(tok, uuid(2), "", `{"reason":"spam"}`); r.StatusCode != 429 {
		t.Errorf("flag over the limit: %d", r.StatusCode)
	}
	// Reads are not limited.
	for i := 0; i < 20; i++ {
		if r := e.get("/v1/reports", nil, nil); r.StatusCode != 200 {
			t.Fatalf("read %d: %d", i, r.StatusCode)
		}
	}

	// The IP bucket (5/h) is shared by installs behind one address: 3 used above.
	for i := 0; i < 2; i++ {
		if r := e.post(token(10+i), payload(uuid(10+i), map[string]any{"fountainID": "422774692"})); r.StatusCode != 201 {
			t.Fatalf("other install %d: %d", i, r.StatusCode)
		}
	}
	r = e.post(token(12), payload(uuid(12), map[string]any{"fountainID": "422774693"}))
	if p := errOf(t, r); r.StatusCode != 429 || p.reason != "ip" || r.Headers["Retry-After"] != "3600" {
		t.Errorf("ip bucket: %d %+v %v", r.StatusCode, p, r.Headers)
	}
	// A different address is fine.
	r = e.do(call{method: "POST", path: "/v1/reports", headers: jsonHeaders(token(12)), body: payload(uuid(12), map[string]any{"fountainID": "422774693"}), ip: "198.51.100.9"})
	if r.StatusCode != 201 {
		t.Errorf("other address: %d %s", r.StatusCode, r.Body)
	}

	// The next clock hour starts clean.
	e.now = e.now.Add(time.Hour)
	if r := e.post(tok, payload(uuid(30), map[string]any{"fountainID": "422774693", "date": e.now.Add(-time.Minute).Format(time.RFC3339)})); r.StatusCode != 201 {
		t.Errorf("next hour: %d %s", r.StatusCode, r.Body)
	}
}

func TestOneReportPerFountainPer20Minutes(t *testing.T) {
	e := newEnv(t)
	tok := token(1)
	if r := e.post(tok, payload(uuid(1), nil)); r.StatusCode != 201 {
		t.Fatal(r.Body)
	}
	r := e.post(tok, payload(uuid(2), nil))
	p := errOf(t, r)
	if r.StatusCode != 429 || p.reason != "fountain" || r.Headers["Retry-After"] != "1200" {
		t.Errorf("second report: %d %+v %v", r.StatusCode, p, r.Headers)
	}
	// Another fountain is fine, and the rejected report was not stored.
	if r := e.post(tok, payload(uuid(3), map[string]any{"fountainID": "422640291"})); r.StatusCode != 201 {
		t.Errorf("other fountain: %d", r.StatusCode)
	}
	if e.mem.Stored(uuid(2)) != nil {
		t.Error("a rate limited report was stored")
	}
	e.now = e.now.Add(20 * time.Minute)
	if r := e.post(tok, payload(uuid(2), map[string]any{"date": e.now.Format(time.RFC3339)})); r.StatusCode != 201 {
		t.Errorf("after the window: %d %s", r.StatusCode, r.Body)
	}
}

func TestDelete(t *testing.T) {
	e := newEnv(t)
	id, tok, _ := e.submit(nil)

	r := e.delete(token(777), id)
	if r.StatusCode != 403 || errOf(t, r).code != "not_owner" {
		t.Errorf("other install: %d %s", r.StatusCode, r.Body)
	}
	if e.mem.Stored(id) == nil {
		t.Fatal("a stranger deleted the report")
	}
	// Case of the id in the path does not matter.
	if r := e.delete(tok, strings.ToLower(id)); r.StatusCode != 204 || r.Body != "" {
		t.Errorf("owner: %d %q", r.StatusCode, r.Body)
	}
	if e.mem.Stored(id) != nil || len(ids(t, e.get("/v1/reports", nil, nil))) != 0 {
		t.Error("report still there")
	}
	for name, id := range map[string]string{"again": id, "never existed": uuid(4242)} {
		if r := e.delete(tok, id); r.StatusCode != 204 {
			t.Errorf("%s: %d", name, r.StatusCode)
		}
	}
	if r := e.delete(tok, "not-a-uuid"); r.StatusCode != 422 || errOf(t, r).code != "invalid_id" {
		t.Errorf("bad id: %d %s", r.StatusCode, r.Body)
	}
	if r := e.do(call{method: "DELETE", path: "/v1/reports/" + id}); r.StatusCode != 401 {
		t.Errorf("no install: %d", r.StatusCode)
	}
	// 403 and 204 both report the bucket.
	if r := e.delete(tok, id); r.Headers["RateLimit-Limit"] != "1000" {
		t.Errorf("headers: %v", r.Headers)
	}
}

func TestFlagAutoHide(t *testing.T) {
	e := newEnv(t)
	id, owner, _ := e.submit(nil)
	flagAs := func(n int, ip string) events.APIGatewayV2HTTPResponse {
		return e.flag(token(100+n), id, ip, `{"reason":"offensive"}`)
	}
	visible := func() bool {
		return len(ids(t, e.get("/v1/reports", nil, nil))) == 1 &&
			len(ids(t, e.get("/v1/fountains/"+fountain+"/reports", nil, nil))) == 1
	}

	// Always 204: first flag, the same install again, the owner, a missing report.
	if r := flagAs(1, "198.51.100.1"); r.StatusCode != 204 || r.Body != "" || r.Headers["RateLimit-Limit"] == "" {
		t.Errorf("first flag: %d %v", r.StatusCode, r.Headers)
	}
	if r := flagAs(1, "198.51.100.1"); r.StatusCode != 204 {
		t.Errorf("repeat: %d", r.StatusCode)
	}
	if r := e.flag(owner, id, "198.51.100.50", `{"reason":"spam"}`); r.StatusCode != 204 {
		t.Errorf("owner: %d", r.StatusCode)
	}
	if r := e.flag(token(100), uuid(4242), "", `{"reason":"spam"}`); r.StatusCode != 204 {
		t.Errorf("missing report: %d", r.StatusCode)
	}
	// Three throwaway tokens behind one address count once.
	for n := 2; n <= 4; n++ {
		flagAs(n, "198.51.100.1")
	}
	if got := e.mem.Stored(id).FlagCount; got != 1 {
		t.Errorf("flagCount after same-address flags = %d, want 1", got)
	}
	// The second distinct flagger (install and address): still visible.
	flagAs(5, "198.51.100.2")
	if got := e.mem.Stored(id).FlagCount; got != 2 || !visible() {
		t.Errorf("flagCount = %d, visible = %v", got, visible())
	}
	// The third distinct flagger hides it from every read.
	if r := flagAs(6, "198.51.100.3"); r.StatusCode != 204 {
		t.Fatalf("third flag: %d", r.StatusCode)
	}
	rec := e.mem.Stored(id)
	if !rec.Hidden || rec.HiddenBy != "flags" || rec.FlagCount != 3 {
		t.Errorf("record = %+v", rec)
	}
	if n := len(ids(t, e.get("/v1/reports", nil, nil))) + len(ids(t, e.get("/v1/fountains/"+fountain+"/reports", nil, nil))); n != 0 {
		t.Errorf("hidden report still listed (%d)", n)
	}
	if m := decode(t, e.get("/v1/summaries", nil, nil))["summaries"].(map[string]any); len(m) != 0 {
		t.Errorf("hidden report still in summaries: %v", m)
	}
	// The owner may still delete it, and flags on a hidden report are ignored.
	if r := flagAs(7, "198.51.100.4"); r.StatusCode != 204 || e.mem.Stored(id).FlagCount != 3 {
		t.Errorf("flag on hidden: %d count %d", r.StatusCode, e.mem.Stored(id).FlagCount)
	}
	// A restored (reviewed) report is never auto-hidden again.
	e.mem.Restore(id)
	for n := 10; n < 16; n++ {
		flagAs(n, fmt.Sprintf("192.0.2.%d", n))
	}
	if rec := e.mem.Stored(id); rec.Hidden || rec.FlagCount < 3 {
		t.Errorf("reviewed report: %+v", rec)
	}
}

func TestFlagValidation(t *testing.T) {
	e := newEnv(t)
	id, _, _ := e.submit(nil)
	for _, tc := range []struct {
		name, body string
		status     int
		code       string
	}{
		{"offensive", `{"reason":"offensive"}`, 204, ""},
		{"spam", `{"reason":"spam"}`, 204, ""},
		{"false", `{"reason":"false"}`, 204, ""},
		{"unknown reason", `{"reason":"rude"}`, 422, "invalid_reason"},
		{"missing", `{}`, 422, "invalid_reason"},
		{"null", `{"reason":null}`, 422, "invalid_reason"},
		{"number", `{"reason":5}`, 422, "invalid_reason"},
		{"malformed", `{"reason":`, 400, "bad_request"},
		{"empty", ``, 400, "bad_request"},
	} {
		r := e.flag(token(50), id, "", tc.body)
		if r.StatusCode != tc.status || (tc.code != "" && errOf(t, r).code != tc.code) {
			t.Errorf("%s: %d %s", tc.name, r.StatusCode, r.Body)
		}
	}
	if r := e.flag(token(50), "bad", "", `{"reason":"spam"}`); r.StatusCode != 422 || errOf(t, r).code != "invalid_id" {
		t.Errorf("bad id: %d", r.StatusCode)
	}
	if r := e.do(call{method: "POST", path: "/v1/reports/" + id + "/flag", body: `{"reason":"spam"}`, headers: map[string]string{"Content-Type": "application/json"}}); r.StatusCode != 401 {
		t.Errorf("no install: %d", r.StatusCode)
	}
	if r := e.do(call{method: "POST", path: "/v1/reports/" + id + "/flag", body: `{"reason":"spam"}`, headers: map[string]string{"X-Toret-Install": token(50)}}); r.StatusCode != 415 {
		t.Errorf("no content type: %d", r.StatusCode)
	}
}

func TestUnknownRoute(t *testing.T) {
	e := newEnv(t)
	if r := e.do(call{method: "GET", path: "/v2/anything"}); r.StatusCode != 404 {
		t.Errorf("unknown route: %d", r.StatusCode)
	}
}

func TestStoreFailureIs503(t *testing.T) {
	e := newEnv(t)
	e.mem.Err = fmt.Errorf("%w: throttled", store.ErrUnavailable)
	for name, r := range map[string]events.APIGatewayV2HTTPResponse{
		"list":    e.get("/v1/reports", nil, nil),
		"summary": e.get("/v1/summaries", nil, nil),
		"post":    e.post(token(1), payload(uuid(1), nil)),
	} {
		if r.StatusCode != 503 || r.Headers["Retry-After"] == "" || errOf(t, r).code != "unavailable" {
			t.Errorf("%s: %d %v", name, r.StatusCode, r.Headers)
		}
	}
	e.mem.Err = errBoom
	if r := e.get("/v1/reports", nil, nil); r.StatusCode != 500 || errOf(t, r).code != "internal" {
		t.Errorf("unknown failure: %d", r.StatusCode)
	}
	if !strings.Contains(e.logs.String(), `"msg":"request failed"`) {
		t.Error("failures must be logged")
	}
}

func TestPepperFailureIs503ThenRecovers(t *testing.T) {
	failing := true
	calls := 0
	e := newEnv(t, func(c *Config) {
		c.Pepper = func(context.Context) ([]byte, error) {
			calls++
			if failing {
				return nil, errBoom
			}
			return pepper, nil
		}
	})
	if r := e.post(token(1), payload(uuid(1), nil)); r.StatusCode != 503 {
		t.Errorf("pepper down: %d", r.StatusCode)
	}
	failing = false
	for i := 0; i < 3; i++ {
		e.post(token(1), payload(uuid(1), nil))
	}
	if calls != 2 {
		t.Errorf("pepper read %d times, want 1 failure + 1 success then cached", calls)
	}
}

type panicStore struct{ *store.Memory }

func (panicStore) Feed(context.Context, time.Time, int) ([]store.Record, error) { panic("oops") }

func TestPanicIs500(t *testing.T) {
	e := newEnv(t)
	e.h.cfg.Store = panicStore{e.mem}
	r := e.get("/v1/reports", nil, nil)
	if r.StatusCode != 500 || errOf(t, r).code != "internal" {
		t.Errorf("panic: %d %s", r.StatusCode, r.Body)
	}
}
