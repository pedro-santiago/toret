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

	r, err := l.Fountain(ctx, base, "inst", "421310659")
	if err != nil || !r.Allowed {
		t.Fatalf("first: %+v, %v", r, err)
	}
	r, _ = l.Fountain(ctx, base, "inst", "421310659")
	// 09:41:30 sits in the window 09:40:00-10:00:00, so 1110 s are left.
	if r.Allowed || r.Scope != ScopeFountain || r.RetryAfter != 1110 || r.Remaining != 39 {
		t.Errorf("second: %+v", r)
	}
	if r, _ := l.Fountain(ctx, base, "inst", "422640291"); !r.Allowed {
		t.Errorf("another fountain must pass: %+v", r)
	}
	if r, _ := l.Fountain(ctx, base, "someone-else", "421310659"); !r.Allowed {
		t.Errorf("another install must pass: %+v", r)
	}
	now = now.Add(20 * time.Minute)
	if r, _ := l.Fountain(ctx, base, "inst", "421310659"); !r.Allowed {
		t.Errorf("next window: %+v", r)
	}
	// Retry-After is bounded by the window and is at least one second.
	now = time.Date(2026, 10, 12, 9, 59, 59, 999_000_000, time.UTC)
	l.Fountain(ctx, base, "x", "1")
	if r, _ := l.Fountain(ctx, base, "x", "1"); r.RetryAfter != 1 {
		t.Errorf("last millisecond: %+v", r)
	}
}
