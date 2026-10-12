// Package ratelimit implements the write limits of docs/backend/api.md
// section 4 on top of atomic counters in the store: fixed windows, one counter
// per (scope, key, window).
package ratelimit

import (
	"context"
	"strconv"
	"time"
)

// Counter is the store operation the limiter needs.
type Counter interface {
	Incr(ctx context.Context, key string, limit int, expires time.Time) (n int, allowed bool, err error)
}

// Config holds the limits. A zero field is replaced by its Defaults value.
//
// Install tokens are free to make, so the install buckets only keep an honest
// client from hammering; what actually bounds abuse is the source-address
// buckets (IPv6 masked to a /64, see handle.IPKey) and the global ceiling.
type Config struct {
	InstallPerHour   int           // writes per install per clock hour
	IPPerHour        int           // writes per source address per clock hour
	FountainWindow   time.Duration // one report per install and fountain per window
	IPFountainPerWin int           // reports per source address and fountain per FountainWindow, whatever the install
	GlobalPerHour    int           // writes of every caller together per clock hour
}

// Defaults are the contract's numbers.
//
// GlobalPerHour times the 37 hourly windows that a 36 h summary read can touch
// must stay under the API's summary read cap (a test pins it), so a flood cannot
// push genuine reports out of /v1/summaries.
var Defaults = Config{
	InstallPerHour: 40, IPPerHour: 300, FountainWindow: 20 * time.Minute,
	IPFountainPerWin: 5, GlobalPerHour: 200,
}

// Scopes name the bucket that tripped, for logs and error.reason.
const (
	ScopeInstall    = "install"
	ScopeIP         = "ip"
	ScopeFountain   = "fountain"
	ScopeIPFountain = "ip_fountain"
	ScopeGlobal     = "global"
)

// Result describes one check. Limit, Remaining and Reset always describe the
// install bucket (the RateLimit-* headers), whichever bucket denied.
type Result struct {
	Allowed    bool
	Scope      string // the bucket that denied; "" when allowed
	RetryAfter int    // seconds, at least 1, when denied
	Limit      int
	Remaining  int
	Reset      int // seconds until the install window ends
}

// Limiter checks and counts writes.
type Limiter struct {
	Counter Counter
	Config  Config
	Now     func() time.Time
}

// New returns a Limiter with the default limits.
func New(c Counter, now func() time.Time) *Limiter {
	return &Limiter{Counter: c, Config: Defaults, Now: now}
}

func window(now time.Time, size time.Duration) (index int64, end time.Time) {
	sec := int64(size / time.Second)
	index = now.Unix() / sec
	return index, time.Unix((index+1)*sec, 0).UTC()
}

func secondsUntil(now, end time.Time) int {
	s := int((end.Sub(now) + time.Second - 1) / time.Second)
	return max(s, 1)
}

func key(scope, who string, index int64) string {
	return "RL#" + scope + "#" + who + "#" + strconv.FormatInt(index, 10)
}

// Write counts one write against the install and IP hourly buckets. It
// stops at the first bucket that is full (earlier ones stay counted).
func (l *Limiter) Write(ctx context.Context, installHash, ipHash string) (Result, error) {
	cfg := l.cfg()
	now := l.Now()
	idx, end := window(now, time.Hour)
	expires := end.Add(time.Hour)
	res := Result{Limit: cfg.InstallPerHour, Reset: secondsUntil(now, end)}

	n, ok, err := l.Counter.Incr(ctx, key("INSTALL", installHash, idx), cfg.InstallPerHour, expires)
	if err != nil {
		return res, err
	}
	res.Remaining = max(cfg.InstallPerHour-n, 0)
	if !ok {
		res.Scope, res.RetryAfter = ScopeInstall, res.Reset
		return res, nil
	}
	if _, ok, err = l.Counter.Incr(ctx, key("IP", ipHash, idx), cfg.IPPerHour, expires); err != nil {
		return res, err
	}
	if !ok {
		res.Scope, res.RetryAfter = ScopeIP, res.Reset
		return res, nil
	}
	res.Allowed = true
	return res, nil
}

// Fountain counts one report against the install-and-fountain gate and the
// address-and-fountain gate (which a fresh install token does not reset), and
// returns prev with Allowed, Scope and RetryAfter updated.
func (l *Limiter) Fountain(ctx context.Context, prev Result, installHash, ipHash, fountainID string) (Result, error) {
	cfg := l.cfg()
	now := l.Now()
	idx, end := window(now, cfg.FountainWindow)
	expires := end.Add(time.Hour)
	_, ok, err := l.Counter.Incr(ctx, key("FOUNTAIN", installHash+"."+fountainID, idx), 1, expires)
	if err != nil {
		return prev, err
	}
	scope := ScopeFountain
	if ok {
		_, ok, err = l.Counter.Incr(ctx, key("IPFOUNTAIN", ipHash+"."+fountainID, idx), cfg.IPFountainPerWin, expires)
		if err != nil {
			return prev, err
		}
		scope = ScopeIPFountain
	}
	if !ok {
		prev.Allowed, prev.Scope, prev.RetryAfter = false, scope, secondsUntil(now, end)
	}
	return prev, nil
}

// Global counts one write against the ceiling shared by every caller: the
// circuit breaker that bounds the table's write cost whatever the attacker
// rotates. Callers run it after every per-caller gate so that a request refused
// there never spends the shared budget.
func (l *Limiter) Global(ctx context.Context, prev Result) (Result, error) {
	cfg := l.cfg()
	now := l.Now()
	idx, end := window(now, time.Hour)
	_, ok, err := l.Counter.Incr(ctx, "RL#GLOBAL#"+strconv.FormatInt(idx, 10), cfg.GlobalPerHour, end.Add(time.Hour))
	if err != nil {
		return prev, err
	}
	if !ok {
		prev.Allowed, prev.Scope, prev.RetryAfter = false, ScopeGlobal, secondsUntil(now, end)
	}
	return prev, nil
}

func (l *Limiter) cfg() Config {
	c := l.Config
	if c.InstallPerHour == 0 {
		c.InstallPerHour = Defaults.InstallPerHour
	}
	if c.IPPerHour == 0 {
		c.IPPerHour = Defaults.IPPerHour
	}
	if c.FountainWindow == 0 {
		c.FountainWindow = Defaults.FountainWindow
	}
	if c.IPFountainPerWin == 0 {
		c.IPFountainPerWin = Defaults.IPFountainPerWin
	}
	if c.GlobalPerHour == 0 {
		c.GlobalPerHour = Defaults.GlobalPerHour
	}
	return c
}
