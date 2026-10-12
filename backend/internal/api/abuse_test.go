package api

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/pedro-santiago/toret/backend/internal/ratelimit"
	"github.com/pedro-santiago/toret/backend/internal/reports"
	"github.com/pedro-santiago/toret/backend/internal/store"
)

// postFrom is a POST from a given source address.
func (e *env) postFrom(ip, tok, body string) int {
	e.t.Helper()
	return e.do(call{method: "POST", path: "/v1/reports", headers: jsonHeaders(tok), body: body, ip: ip}).StatusCode
}

// One host with a whole IPv6 /64 must share one IP bucket, however many
// addresses and install tokens it uses.
func TestIPv6PrefixSharesTheIPBucket(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.Limits.IPPerHour = 3 })
	fountains := []string{"421310659", "422640291", "422640299", "422640314"}
	for i := 0; i < 3; i++ {
		ip := fmt.Sprintf("2001:db8:1:2:%x::%x", i+1, i+7)
		if st := e.postFrom(ip, token(i), payload(uuid(i+1), map[string]any{"fountainID": fountains[i]})); st != 201 {
			t.Fatalf("report %d: %d", i, st)
		}
	}
	r := e.do(call{method: "POST", path: "/v1/reports", headers: jsonHeaders(token(9)), ip: "2001:db8:1:2:dead:beef::1",
		body: payload(uuid(9), map[string]any{"fountainID": fountains[3]})})
	if p := errOf(t, r); r.StatusCode != 429 || p.reason != "ip" {
		t.Errorf("4th address of the /64: %d %+v", r.StatusCode, p)
	}
	// The next /64, and an IPv4 address, are separate buckets.
	if st := e.postFrom("2001:db8:1:3::1", token(10), payload(uuid(10), map[string]any{"fountainID": fountains[3]})); st != 201 {
		t.Errorf("another /64: %d", st)
	}
	if st := e.postFrom("198.51.100.9", token(11), payload(uuid(11), map[string]any{"fountainID": "422774692"})); st != 201 {
		t.Errorf("IPv4: %d", st)
	}
}

// A new X-Toret-Install each time resets the install gates, so the address and
// fountain gate must hold on its own.
func TestFreshTokensDoNotResetTheAddressFountainGate(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.Limits.IPFountainPerWin = 2 })
	for i := 0; i < 2; i++ {
		if st := e.postFrom("", token(i), payload(uuid(i+1), nil)); st != 201 {
			t.Fatalf("report %d: %d", i, st)
		}
	}
	r := e.post(token(3), payload(uuid(3), nil))
	if p := errOf(t, r); r.StatusCode != 429 || p.code != "rate_limited" || p.reason != ratelimit.ScopeIPFountain || r.Headers["Retry-After"] != "1200" {
		t.Errorf("third fresh token, same address and fountain: %d %+v %v", r.StatusCode, p, r.Headers)
	}
	if e.mem.Stored(uuid(3)) != nil {
		t.Error("a refused report was stored")
	}
	// Another fountain, another address, and the next window all pass.
	if st := e.post(token(4), payload(uuid(4), map[string]any{"fountainID": "422640291"})).StatusCode; st != 201 {
		t.Errorf("another fountain: %d", st)
	}
	if st := e.postFrom("198.51.100.9", token(5), payload(uuid(5), nil)); st != 201 {
		t.Errorf("another address: %d", st)
	}
	e.now = e.now.Add(20 * time.Minute)
	if st := e.post(token(6), payload(uuid(6), map[string]any{"date": e.now.Format(time.RFC3339)})).StatusCode; st != 201 {
		t.Errorf("next window: %d", st)
	}
}

// The circuit breaker: every caller together may write GlobalPerHour times an
// hour, whatever tokens and addresses they rotate.
func TestGlobalWriteCeiling(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.Limits.GlobalPerHour = 3 })
	var first string
	for i := 0; i < 3; i++ {
		id, _, r := e.submit(map[string]any{"fountainID": []string{"421310659", "422640291", "422640299"}[i]})
		if i == 0 {
			first = id
		}
		if r.Headers["RateLimit-Limit"] != "1000" {
			t.Errorf("write %d: %v", i, r.Headers)
		}
	}
	// A fourth write from a brand new install and address.
	n := e.fresh()
	r := e.do(call{method: "POST", path: "/v1/reports", headers: jsonHeaders(token(n)), ip: "198.51.100.77",
		body: payload(uuid(n), map[string]any{"fountainID": "422640314"})})
	if p := errOf(t, r); r.StatusCode != 429 || p.code != "rate_limited" || p.reason != ratelimit.ScopeGlobal || r.Headers["Retry-After"] != "3600" {
		t.Fatalf("4th write: %d %+v %v", r.StatusCode, p, r.Headers)
	}
	if e.mem.Stored(uuid(n)) != nil {
		t.Error("a refused report was stored")
	}
	// Deletes and flags are writes too.
	tok := token(1)
	if r := e.delete(tok, first); r.StatusCode != 429 || errOf(t, r).reason != ratelimit.ScopeGlobal {
		t.Errorf("delete over the ceiling: %d", r.StatusCode)
	}
	if r := e.flag(token(50), first, "", `{"reason":"spam"}`); r.StatusCode != 429 {
		t.Errorf("flag over the ceiling: %d", r.StatusCode)
	}
	// Reads and an idempotent retry of a stored report are not writes.
	if r := e.get("/v1/summaries", nil, nil); r.StatusCode != 200 {
		t.Errorf("summaries: %d", r.StatusCode)
	}
	if r := e.get("/v1/reports", nil, nil); r.StatusCode != 200 || len(ids(t, r)) != 3 {
		t.Errorf("feed: %d %s", r.StatusCode, r.Body)
	}
	if r := e.post(tok, payload(first, nil)); r.StatusCode != 200 {
		t.Errorf("retry of a stored report: %d", r.StatusCode)
	}
	// The next clock hour starts clean.
	e.now = e.now.Add(time.Hour)
	if r := e.delete(tok, first); r.StatusCode != 204 {
		t.Errorf("next hour: %d", r.StatusCode)
	}
}

// A request refused by a per-caller gate has not spent the shared budget.
func TestPerCallerDenialDoesNotSpendTheGlobalBudget(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.Limits.GlobalPerHour = 2; c.Limits.InstallPerHour = 1 })
	tok := token(1)
	if r := e.post(tok, payload(uuid(1), nil)); r.StatusCode != 201 {
		t.Fatal(r.Body)
	}
	for i := 0; i < 5; i++ { // install bucket full
		if r := e.post(tok, payload(uuid(10+i), map[string]any{"fountainID": "422640291"})); errOf(t, r).reason != "install" {
			t.Fatalf("attempt %d: %s", i, r.Body)
		}
	}
	// Same install and fountain: the 20 minute gate.
	e2 := newEnv(t, func(c *Config) { c.Limits.GlobalPerHour = 2 })
	e2.post(token(1), payload(uuid(1), nil))
	for i := 0; i < 5; i++ {
		e2.post(token(1), payload(uuid(10+i), nil))
	}
	if r := e2.post(token(2), payload(uuid(2), map[string]any{"fountainID": "422640291"})); r.StatusCode != 201 {
		t.Errorf("a refused flood spent the global budget: %d %s", r.StatusCode, r.Body)
	}
	if r := e.post(token(2), payload(uuid(2), map[string]any{"fountainID": "422640291"})); r.StatusCode != 201 {
		t.Errorf("install-bucket denials spent the global budget: %d %s", r.StatusCode, r.Body)
	}
}

// The ceiling times the hourly windows a 36 h summary read can touch must fit
// under the read cap, or a flood could push genuine reports out of it.
func TestGlobalCeilingFitsTheSummaryReadCap(t *testing.T) {
	windows := int(reports.Freshness/time.Hour) + 1
	if got := ratelimit.Defaults.GlobalPerHour * windows; got > summaryReadCap {
		t.Errorf("%d writes an hour x %d windows = %d, above the summary read cap %d",
			ratelimit.Defaults.GlobalPerHour, windows, got, summaryReadCap)
	}
}

func TestSummariesWarnWhenTruncated(t *testing.T) {
	e := newEnv(t)
	for i := 0; i < summaryReadCap; i++ {
		e.mem.PutReport(context.Background(), store.Record{ID: fmt.Sprintf("R%05d", i), FountainID: fountain, State: "running",
			Date: epoch.Add(-time.Minute), Author: "Visitante 000000", InstallHash: "x"})
	}
	if r := e.get("/v1/summaries", nil, nil); r.StatusCode != 200 {
		t.Fatal(r.StatusCode)
	}
	if !strings.Contains(e.logs.String(), "summaries truncated") {
		t.Error("reading the cap's worth of reports must log a warning")
	}
}

// A banned address is refused whatever token it brings, and so is its whole
// IPv6 /64.
func TestBanByAddress(t *testing.T) {
	e := newEnv(t)
	e.mem.BanIP(ipHashOf("203.0.113.7"))
	e.mem.BanIP(ipHashOf("2001:db8:1:2::1"))

	for i := 0; i < 3; i++ { // a new token each time
		if r := e.post(token(i), payload(uuid(i+1), nil)); r.StatusCode != 403 || errOf(t, r).code != "forbidden" {
			t.Errorf("banned address, token %d: %d %s", i, r.StatusCode, r.Body)
		}
	}
	if r := e.delete(token(7), uuid(1)); r.StatusCode != 403 {
		t.Errorf("banned address delete: %d", r.StatusCode)
	}
	if r := e.flag(token(8), uuid(1), "", `{"reason":"spam"}`); r.StatusCode != 403 {
		t.Errorf("banned address flag: %d", r.StatusCode)
	}
	if st := e.postFrom("2001:db8:1:2:9:9:9:9", token(1), payload(uuid(1), nil)); st != 403 {
		t.Errorf("another address of a banned /64: %d", st)
	}
	if e.mem.Calls["Incr"] != 0 {
		t.Error("a banned address consumed counters")
	}
	if st := e.postFrom("198.51.100.9", token(1), payload(uuid(1), nil)); st != 201 {
		t.Errorf("another address: %d", st)
	}
	if r := e.get("/v1/reports", nil, nil); r.StatusCode != 200 {
		t.Errorf("reads stay open: %d", r.StatusCode)
	}
}

// A report dated a few minutes ahead (a fast phone clock) is stored as of now,
// so it cannot outrank the genuine reports that follow it.
func TestFutureDateIsClampedToNow(t *testing.T) {
	e := newEnv(t)
	future := e.now.Add(9 * time.Minute).Format(time.RFC3339)
	id, tok, r := e.submit(map[string]any{"state": "dry", "date": future})
	if rec := e.mem.Stored(id); rec == nil || !rec.Date.Equal(e.now) || !strings.Contains(r.Body, `"date":"2026-10-12T12:00:00Z"`) {
		t.Fatalf("stored = %+v, body %s", rec, r.Body)
	}
	if rec := e.mem.Stored(id); !rec.CreatedAt.Equal(rec.Date) {
		t.Errorf("createdAt %v, date %v", rec.CreatedAt, rec.Date)
	}
	// The retry gets the stored report, not the date it sent.
	if again := e.post(tok, payload(id, map[string]any{"state": "dry", "date": future})); again.StatusCode != 200 || again.Body != r.Body {
		t.Errorf("retry: %d %s", again.StatusCode, again.Body)
	}

	// Someone reports the fountain running five minutes later: that one decides.
	e.now = e.now.Add(5 * time.Minute)
	e.submit(map[string]any{"state": "running", "date": e.now.Format(time.RFC3339)})
	e.now = e.now.Add(summaryCacheTime)
	sum := decode(t, e.get("/v1/summaries", nil, nil))["summaries"].(map[string]any)[fountain].(map[string]any)
	if sum["state"] != "running" || sum["reportCount"].(float64) != 2 {
		t.Errorf("summary = %v", sum)
	}
	// A date at or before now is kept as sent; the past window is unchanged.
	past := e.now.Add(-2 * time.Hour).Truncate(time.Second)
	id2, _, _ := e.submit(map[string]any{"fountainID": "422640291", "date": past.Format(time.RFC3339)})
	if rec := e.mem.Stored(id2); !rec.Date.Equal(past) {
		t.Errorf("past date moved: %v", rec.Date)
	}
}

func TestLogClientIsBoundedAndClean(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"1.0.0+42", "1.0.0+42"},
		{"", ""},
		{"1.0.0\n{\"level\":\"ERROR\"} \x00 é", "1.0.0levelERROR"},
		{strings.Repeat("a", 8000), strings.Repeat("a", 32)},
		{strings.Repeat("!", 8000) + "ok", "ok"},
	} {
		if got := logClient(tc.in); got != tc.want {
			t.Errorf("logClient(%.40q) = %q, want %q", tc.in, got, tc.want)
		}
	}

	e := newEnv(t)
	h := jsonHeaders(token(1))
	h["X-Toret-Client"] = strings.Repeat("x", 8000)
	e.do(call{method: "POST", path: "/v1/reports", headers: h, body: payload(uuid(1), nil)})
	if strings.Contains(e.logs.String(), strings.Repeat("x", 33)) || !strings.Contains(e.logs.String(), `"client":"`+strings.Repeat("x", 32)+`"`) {
		t.Errorf("log line = %s", e.logs.String())
	}
}
