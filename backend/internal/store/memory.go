package store

import (
	"context"
	"sort"
	"sync"
	"time"
)

// Memory is the in-memory Store used by the tests. It follows the same rules as
// the DynamoDB layout: reads are ordered by DateKey, hidden reports are absent
// from every list, a report is flagged once per install and once per source
// address.
type Memory struct {
	mu       sync.Mutex
	reports  map[string]*Record
	flags    map[string]map[string]bool // report id -> "i:"+installHash / "p:"+ipHash
	bans     map[string]bool
	counters map[string]int
	weather  *Weather
	notices  *Notices

	// Err, when set, is returned by every call (to test the 503 path).
	Err error
	// Calls counts calls by method name.
	Calls map[string]int
}

// NewMemory returns an empty store.
func NewMemory() *Memory {
	return &Memory{
		reports:  map[string]*Record{},
		flags:    map[string]map[string]bool{},
		bans:     map[string]bool{},
		counters: map[string]int{},
		Calls:    map[string]int{},
	}
}

func (m *Memory) enter(name string) error {
	m.Calls[name]++
	return m.Err
}

func clone(r Record) *Record {
	c := r
	c.Tags = append([]string{}, r.Tags...)
	if r.Rating != nil {
		v := *r.Rating
		c.Rating = &v
	}
	return &c
}

// Ban marks an install as banned.
func (m *Memory) Ban(installHash string) { m.mu.Lock(); m.bans[installHash] = true; m.mu.Unlock() }

// HideByOwner mimics the runbook's "hide a report now".
func (m *Memory) HideByOwner(id string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if r := m.reports[id]; r != nil {
		r.Hidden, r.HiddenBy = true, "owner"
	}
}

// Restore mimics the runbook's "restore a report".
func (m *Memory) Restore(id string) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if r := m.reports[id]; r != nil {
		r.Hidden, r.HiddenBy, r.FlagCount, r.Reviewed = false, "", 0, true
	}
}

// Counter reads a rate-limit counter.
func (m *Memory) Counter(key string) int { m.mu.Lock(); defer m.mu.Unlock(); return m.counters[key] }

// Stored returns a copy of a stored record, hidden or not.
func (m *Memory) Stored(id string) *Record {
	m.mu.Lock()
	defer m.mu.Unlock()
	if r := m.reports[id]; r != nil {
		return clone(*r)
	}
	return nil
}

func (m *Memory) GetReport(_ context.Context, id string) (*Record, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.enter("GetReport"); err != nil {
		return nil, err
	}
	if r := m.reports[id]; r != nil {
		return clone(*r), nil
	}
	return nil, nil
}

func (m *Memory) PutReport(_ context.Context, r Record) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.enter("PutReport"); err != nil {
		return false, err
	}
	if _, taken := m.reports[r.ID]; taken {
		return false, nil
	}
	m.reports[r.ID] = clone(r)
	return true, nil
}

func (m *Memory) DeleteReport(_ context.Context, id, installHash string) (DeleteOutcome, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.enter("DeleteReport"); err != nil {
		return NotFound, err
	}
	r := m.reports[id]
	switch {
	case r == nil:
		return NotFound, nil
	case r.InstallHash != installHash:
		return NotOwner, nil
	}
	delete(m.reports, id)
	return Deleted, nil
}

func (m *Memory) list(match func(*Record) bool, cutoff time.Time, limit int) []Record {
	floor := CutoffKey(cutoff)
	var rows []*Record
	for _, r := range m.reports {
		if r.Hidden || !match(r) || DateKey(r.Date, r.ID) <= floor {
			continue
		}
		rows = append(rows, r)
	}
	sort.Slice(rows, func(i, j int) bool {
		return DateKey(rows[i].Date, rows[i].ID) > DateKey(rows[j].Date, rows[j].ID)
	})
	if len(rows) > limit {
		rows = rows[:limit]
	}
	out := make([]Record, len(rows))
	for i, r := range rows {
		out[i] = *clone(*r)
	}
	return out
}

func (m *Memory) Feed(_ context.Context, cutoff time.Time, limit int) ([]Record, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.enter("Feed"); err != nil {
		return nil, err
	}
	return m.list(func(*Record) bool { return true }, cutoff, limit), nil
}

func (m *Memory) Fountain(_ context.Context, fountainID string, cutoff time.Time, limit int) ([]Record, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.enter("Fountain"); err != nil {
		return nil, err
	}
	return m.list(func(r *Record) bool { return r.FountainID == fountainID }, cutoff, limit), nil
}

func (m *Memory) Banned(_ context.Context, installHash string) (bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.enter("Banned"); err != nil {
		return false, err
	}
	return m.bans[installHash], nil
}

func (m *Memory) Flag(_ context.Context, f FlagRequest) (FlagOutcome, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.enter("Flag"); err != nil {
		return FlagIgnored, err
	}
	r := m.reports[f.ReportID]
	if r == nil || r.Hidden || r.InstallHash == f.InstallHash {
		return FlagIgnored, nil
	}
	seen := m.flags[f.ReportID]
	if seen == nil {
		seen = map[string]bool{}
		m.flags[f.ReportID] = seen
	}
	if seen["i:"+f.InstallHash] || seen["p:"+f.IPHash] {
		return FlagDuplicate, nil
	}
	seen["i:"+f.InstallHash], seen["p:"+f.IPHash] = true, true
	r.FlagCount++
	if r.FlagCount >= HideThreshold && !r.Reviewed {
		r.Hidden, r.HiddenBy = true, "flags"
		return FlagCountedAndHidden, nil
	}
	return FlagCounted, nil
}

func (m *Memory) Incr(_ context.Context, key string, limit int, _ time.Time) (int, bool, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.enter("Incr"); err != nil {
		return 0, false, err
	}
	if m.counters[key] >= limit {
		return m.counters[key], false, nil
	}
	m.counters[key]++
	return m.counters[key], true, nil
}

func (m *Memory) GetWeather(context.Context) (*Weather, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.enter("GetWeather"); err != nil {
		return nil, err
	}
	if m.weather == nil {
		return nil, nil
	}
	w := *m.weather
	return &w, nil
}

func (m *Memory) PutWeather(_ context.Context, w Weather) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.enter("PutWeather"); err != nil {
		return err
	}
	m.weather = &w
	return nil
}

func (m *Memory) GetNotices(context.Context) (*Notices, error) {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.enter("GetNotices"); err != nil {
		return nil, err
	}
	if m.notices == nil {
		return nil, nil
	}
	n := *m.notices
	n.Items = append([]Notice{}, n.Items...)
	return &n, nil
}

func (m *Memory) PutNotices(_ context.Context, n Notices) error {
	m.mu.Lock()
	defer m.mu.Unlock()
	if err := m.enter("PutNotices"); err != nil {
		return err
	}
	n.Items = append([]Notice{}, n.Items...)
	m.notices = &n
	return nil
}
