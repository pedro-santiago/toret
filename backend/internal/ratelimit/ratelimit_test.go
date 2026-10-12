package ratelimit

import (
	"context"
	"testing"
	"time"

	"github.com/pedro-santiago/toret/backend/internal/store"
)

func TestWriteBuckets(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 10, 12, 9, 41, 30, 0, time.UTC)
	mem := store.NewMemory()
	l := New(mem, func() time.Time { return now })
	l.Config = Config{InstallPerHour: 3, IPPerHour: 5}

	// Three writes pass and count down; the fourth trips the install bucket.
	for i, wantRemaining := range []int{2, 1, 0} {
		r, err := l.Write(ctx, "inst", "ip")
		if err != nil || !r.Allowed {
			t.Fatalf("write %d: %+v, %v", i, r, err)
		}
		if r.Remaining != wantRemaining || r.Limit != 3 || r.Reset != 1110 {
			t.Errorf("write %d: %+v", i, r)
		}
	}
	r, _ := l.Write(ctx, "inst", "ip")
	if r.Allowed || r.Scope != ScopeInstall || r.RetryAfter != 1110 || r.Remaining != 0 {
		t.Errorf("4th write: %+v", r)
	}

	// Other installs behind the same address share the IP bucket (5 per hour).
	for i := 0; i < 2; i++ {
		if r, _ := l.Write(ctx, "other", "ip"); !r.Allowed {
			t.Fatalf("other install write %d denied: %+v", i, r)
		}
	}
	r, _ = l.Write(ctx, "third", "ip")
	if r.Allowed || r.Scope != ScopeIP || r.RetryAfter != 1110 || r.Remaining != 2 {
		t.Errorf("ip bucket: %+v", r)
	}

	// The next clock hour starts clean.
	now = now.Add(time.Hour)
	if r, _ := l.Write(ctx, "inst", "ip"); !r.Allowed || r.Remaining != 2 {
		t.Errorf("next hour: %+v", r)
	}
}

func TestFountainGate(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 10, 12, 9, 41, 30, 0, time.UTC)
	mem := store.NewMemory()
	l := New(mem, func() time.Time { return now })
	base := Result{Allowed: true, Limit: 40, Remaining: 39, Reset: 100}

	r, err := l.Fountain(ctx, base, "inst", "ip", "421310659")
	if err != nil || !r.Allowed {
		t.Fatalf("first: %+v, %v", r, err)
	}
	r, _ = l.Fountain(ctx, base, "inst", "ip", "421310659")
	// 09:41:30 sits in the window 09:40:00-10:00:00, so 1110 s are left.
	if r.Allowed || r.Scope != ScopeFountain || r.RetryAfter != 1110 || r.Remaining != 39 {
		t.Errorf("second: %+v", r)
	}
	if r, _ := l.Fountain(ctx, base, "inst", "ip", "422640291"); !r.Allowed {
		t.Errorf("another fountain must pass: %+v", r)
	}
	if r, _ := l.Fountain(ctx, base, "someone-else", "ip2", "421310659"); !r.Allowed {
		t.Errorf("another install must pass: %+v", r)
	}
	now = now.Add(20 * time.Minute)
	if r, _ := l.Fountain(ctx, base, "inst", "ip", "421310659"); !r.Allowed {
		t.Errorf("next window: %+v", r)
	}
	// Retry-After is bounded by the window and is at least one second.
	now = time.Date(2026, 10, 12, 9, 59, 59, 999_000_000, time.UTC)
	l.Fountain(ctx, base, "x", "ipx", "1")
	if r, _ := l.Fountain(ctx, base, "x", "ipx", "1"); r.RetryAfter != 1 {
		t.Errorf("last millisecond: %+v", r)
	}
}

// A fresh install token must not reset the per-fountain gate: the address-and-
// fountain bucket holds across installs, and the next window starts clean.
func TestIPFountainGateIgnoresInstall(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 10, 12, 9, 41, 30, 0, time.UTC)
	l := New(store.NewMemory(), func() time.Time { return now })
	l.Config = Config{IPFountainPerWin: 2}
	base := Result{Allowed: true, Limit: 40, Remaining: 39, Reset: 100}

	for i, inst := range []string{"a", "b"} {
		if r, err := l.Fountain(ctx, base, inst, "ip", "421310659"); err != nil || !r.Allowed {
			t.Fatalf("report %d: %+v, %v", i, r, err)
		}
	}
	r, _ := l.Fountain(ctx, base, "c", "ip", "421310659")
	if r.Allowed || r.Scope != ScopeIPFountain || r.RetryAfter != 1110 || r.Remaining != 39 {
		t.Errorf("third install, same address: %+v", r)
	}
	if r, _ := l.Fountain(ctx, base, "d", "ip", "422640291"); !r.Allowed {
		t.Errorf("another fountain must pass: %+v", r)
	}
	if r, _ := l.Fountain(ctx, base, "e", "other-ip", "421310659"); !r.Allowed {
		t.Errorf("another address must pass: %+v", r)
	}
	// The install gate is checked first and does not spend the address bucket.
	l.Fountain(ctx, base, "a", "ip3", "9")
	if r, _ := l.Fountain(ctx, base, "a", "ip3", "9"); r.Scope != ScopeFountain {
		t.Errorf("repeat by one install: %+v", r)
	}
	now = now.Add(20 * time.Minute)
	if r, _ := l.Fountain(ctx, base, "f", "ip", "421310659"); !r.Allowed {
		t.Errorf("next window: %+v", r)
	}
}

func TestGlobalCeiling(t *testing.T) {
	ctx := context.Background()
	now := time.Date(2026, 10, 12, 9, 41, 30, 0, time.UTC)
	l := New(store.NewMemory(), func() time.Time { return now })
	l.Config = Config{GlobalPerHour: 3}
	base := Result{Allowed: true, Limit: 40, Remaining: 39, Reset: 1110}

	for i := 0; i < 3; i++ {
		if r, err := l.Global(ctx, base); err != nil || !r.Allowed {
			t.Fatalf("write %d: %+v, %v", i, r, err)
		}
	}
	r, _ := l.Global(ctx, base)
	if r.Allowed || r.Scope != ScopeGlobal || r.RetryAfter != 1110 || r.Remaining != 39 {
		t.Errorf("4th write: %+v", r)
	}
	now = now.Add(time.Hour)
	if r, _ := l.Global(ctx, base); !r.Allowed {
		t.Errorf("next hour: %+v", r)
	}
}
