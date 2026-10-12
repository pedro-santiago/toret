package reports

import (
	"math"
	"time"

	"github.com/pedro-santiago/toret/backend/internal/httpx"
	"github.com/pedro-santiago/toret/backend/internal/store"
)

// Summary is one fountain's entry in GET /v1/summaries (api.md section 6.3).
type Summary struct {
	State       string   `json:"state"`
	LatestDate  string   `json:"latestDate"`
	Average     *float64 `json:"average,omitempty"`
	RatingCount int      `json:"ratingCount"`
	ReportCount int      `json:"reportCount"`
}

// Summarise mirrors CommunitySummary.summarising over the reports in the
// freshness window, per fountain. The newest report whose state is not
// unknown decides the state (else the newest overall: a rating alone must not
// reset "running"); it speaks only while now - date <= 36 h. Ratings and counts
// cover every report in the window. A fountain with no report in the window is
// absent, which the client reads as CommunitySummary.empty.
func Summarise(rs []store.Record, now time.Time) map[string]Summary {
	cutoff := now.Add(-Freshness)
	type acc struct {
		decider, newest *store.Record
		sum, ratings    int
		count           int
	}
	by := map[string]*acc{}
	for i := range rs {
		r := &rs[i]
		if r.Date.Before(cutoff) {
			continue
		}
		a := by[r.FountainID]
		if a == nil {
			a = &acc{}
			by[r.FountainID] = a
		}
		a.count++
		if r.Rating != nil {
			a.sum += *r.Rating
			a.ratings++
		}
		if a.newest == nil || newer(r, a.newest) {
			a.newest = r
		}
		if r.State != "unknown" && (a.decider == nil || newer(r, a.decider)) {
			a.decider = r
		}
	}
	out := make(map[string]Summary, len(by))
	for fid, a := range by {
		deciding := a.decider
		if deciding == nil {
			deciding = a.newest
		}
		s := Summary{State: "unknown", LatestDate: httpx.FormatTime(deciding.Date), RatingCount: a.ratings, ReportCount: a.count}
		if now.Sub(deciding.Date) <= Freshness {
			s.State = deciding.State
		}
		if a.ratings > 0 {
			avg := math.Round(float64(a.sum)/float64(a.ratings)*100) / 100
			s.Average = &avg
		}
		out[fid] = s
	}
	return out
}

// newer orders by date, then id, the order of the feed.
func newer(a, b *store.Record) bool {
	if !a.Date.Equal(b.Date) {
		return a.Date.After(b.Date)
	}
	return a.ID > b.ID
}
