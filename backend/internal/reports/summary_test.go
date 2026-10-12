package reports

import (
	"testing"
	"time"

	"github.com/pedro-santiago/toret/backend/internal/store"
)

func rec(id, fountain, state string, rating int, ago time.Duration) store.Record {
	r := store.Record{ID: id, FountainID: fountain, State: state, Date: now.Add(-ago)}
	if rating > 0 {
		r.Rating = &rating
	}
	return r
}

func TestSummarise(t *testing.T) {
	h := time.Hour
	rs := []store.Record{
		// F1: newest says weak, an older one running; a newer rating-only report
		// must not reset the state.
		rec("A", "F1", "running", 5, 5*h),
		rec("B", "F1", "weak", 4, 2*h),
		rec("C", "F1", "unknown", 2, 1*h),
		// F2: only a rating: state unknown, latestDate still returned.
		rec("D", "F2", "unknown", 3, 3*h),
		// F3: exactly 36 h old is still fresh (<=).
		rec("E", "F3", "dry", 0, 36*h),
		// F4: older than 36 h is outside the window, so the fountain is absent.
		rec("F", "F4", "running", 5, 36*h+time.Second),
		// F5: a fresh rating-only report beside an old state: the old state decides
		// but is in the window only if within 36 h.
		rec("G", "F5", "running", 0, 30*h),
		rec("H", "F5", "unknown", 5, 1*h),
	}
	got := Summarise(rs, now)
	if _, ok := got["F4"]; ok {
		t.Error("F4 must be absent")
	}
	f1 := got["F1"]
	if f1.State != "weak" || f1.LatestDate != "2026-10-12T10:00:00Z" || *f1.Average != 3.67 || f1.RatingCount != 3 || f1.ReportCount != 3 {
		t.Errorf("F1 = %+v avg %v", f1, *f1.Average)
	}
	if f2 := got["F2"]; f2.State != "unknown" || f2.LatestDate != "2026-10-12T09:00:00Z" || f2.ReportCount != 1 {
		t.Errorf("F2 = %+v", f2)
	}
	if f3 := got["F3"]; f3.State != "dry" || f3.Average != nil || f3.RatingCount != 0 || f3.ReportCount != 1 || f3.LatestDate != "2026-10-11T00:00:00Z" {
		t.Errorf("F3 = %+v", f3)
	}
	if f5 := got["F5"]; f5.State != "running" || f5.LatestDate != "2026-10-11T06:00:00Z" || *f5.Average != 5 || f5.ReportCount != 2 {
		t.Errorf("F5 = %+v", f5)
	}
	if len(got) != 4 {
		t.Errorf("got %d fountains, want 4", len(got))
	}
}

func TestSummariseTieBreakIsDeterministic(t *testing.T) {
	a := rec("A", "F", "running", 0, time.Hour)
	b := rec("B", "F", "dry", 0, time.Hour)
	for _, rs := range [][]store.Record{{a, b}, {b, a}} {
		if s := Summarise(rs, now)["F"]; s.State != "dry" {
			t.Errorf("same-second tie must go to the larger id: %+v", s)
		}
	}
}
