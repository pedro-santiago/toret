package ingest

import (
	"context"
	"encoding/json"
	"io"
	"log/slog"
	"net/http"
	"net/http/httptest"
	"os"
	"sync/atomic"
	"testing"
	"time"

	"github.com/pedro-santiago/toret/backend/internal/catalogue"
	"github.com/pedro-santiago/toret/backend/internal/smat"
	"github.com/pedro-santiago/toret/backend/internal/store"
	"github.com/pedro-santiago/toret/backend/internal/weather"
)

var now = time.Date(2026, 10, 12, 16, 5, 0, 0, time.UTC)

type rig struct {
	r          *Runner
	mem        *store.Memory
	clock      time.Time
	wCalls     atomic.Int32
	sCalls     atomic.Int32
	wBad, sBad atomic.Bool
}

func newRig(t *testing.T, smatOn bool) *rig {
	t.Helper()
	om, err := os.ReadFile("../weather/testdata/open-meteo.json")
	if err != nil {
		t.Fatal(err)
	}
	cm, err := os.ReadFile("../smat/testdata/mappa_cantieri.json")
	if err != nil {
		t.Fatal(err)
	}
	g := &rig{mem: store.NewMemory(), clock: now}
	ws := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		g.wCalls.Add(1)
		if g.wBad.Load() {
			http.Error(w, "down", 503)
			return
		}
		w.Write(om)
	}))
	ss := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		g.sCalls.Add(1)
		if g.sBad.Load() {
			w.Write([]byte("<html>maintenance</html>"))
			return
		}
		w.Write(cm)
	}))
	t.Cleanup(ws.Close)
	t.Cleanup(ss.Close)
	cat, _ := catalogue.Embedded()
	g.r = &Runner{
		Store: g.mem, Catalogue: cat, Weather: weather.Client{URL: ws.URL}, SMAT: smat.Client{URL: ss.URL},
		SMATEnabled: smatOn, Now: func() time.Time { return g.clock }, Log: slog.New(slog.NewTextHandler(io.Discard, nil)),
	}
	return g
}

func TestWeatherJob(t *testing.T) {
	g := newRig(t, false)
	ctx := context.Background()
	if err := g.r.Run(ctx, JobWeather); err != nil {
		t.Fatal(err)
	}
	w, _ := g.mem.GetWeather(ctx)
	if w == nil || w.TemperatureC != 20.8 || !w.FetchedAt.Equal(now) {
		t.Fatalf("cache = %+v", w)
	}
	// A second invocation inside the window must not call Open-Meteo again.
	g.clock = now.Add(5 * time.Minute)
	g.r.Run(ctx, JobWeather)
	g.clock = now.Add(13 * time.Minute)
	g.r.Run(ctx, JobWeather)
	if g.wCalls.Load() != 1 {
		t.Errorf("upstream called %d times inside 14 minutes", g.wCalls.Load())
	}
	// The next scheduled run (15 minutes) refreshes, even if it fires early.
	g.clock = now.Add(14*time.Minute + 30*time.Second)
	g.r.Run(ctx, JobWeather)
	if g.wCalls.Load() != 2 {
		t.Errorf("upstream called %d times, want 2", g.wCalls.Load())
	}

	// A failing upstream returns an error and keeps the good cache.
	g.wBad.Store(true)
	g.clock = now.Add(time.Hour)
	if err := g.r.Run(ctx, JobWeather); err == nil {
		t.Error("an upstream failure must be reported")
	}
	if w, _ := g.mem.GetWeather(ctx); !w.FetchedAt.Equal(now.Add(14*time.Minute + 30*time.Second)) {
		t.Errorf("the cache was overwritten: %+v", w)
	}
}

func TestSMATIsOffByDefault(t *testing.T) {
	g := newRig(t, false)
	if err := g.r.Run(context.Background(), JobSMAT); err != nil {
		t.Fatal(err)
	}
	if err := g.r.Run(context.Background(), ""); err != nil {
		t.Fatal(err)
	}
	if g.sCalls.Load() != 0 || g.mem.Calls["GetNotices"] != 0 || g.mem.Calls["PutNotices"] != 0 {
		t.Errorf("SMAT_ENABLED=false must be a no-op: %d requests, store %v", g.sCalls.Load(), g.mem.Calls)
	}
}

func TestSMATJob(t *testing.T) {
	g := newRig(t, true)
	ctx := context.Background()
	if err := g.r.Run(ctx, JobSMAT); err != nil {
		t.Fatal(err)
	}
	n, _ := g.mem.GetNotices(ctx)
	if n == nil || len(n.Items) != 15 || !n.FetchedAt.Equal(now) {
		t.Fatalf("cache = %+v", n)
	}
	// Hourly at most.
	g.clock = now.Add(30 * time.Minute)
	g.r.Run(ctx, JobSMAT)
	if g.sCalls.Load() != 1 {
		t.Errorf("upstream called %d times inside the hour", g.sCalls.Load())
	}
	g.clock = now.Add(time.Hour)
	g.r.Run(ctx, JobSMAT)
	if g.sCalls.Load() != 2 {
		t.Errorf("upstream called %d times, want 2", g.sCalls.Load())
	}

	// A broken answer (HTML, not JSON) keeps the last good cache.
	g.sBad.Store(true)
	g.clock = now.Add(3 * time.Hour)
	if err := g.r.Run(ctx, JobSMAT); err == nil {
		t.Error("a broken upstream must be reported")
	}
	if n, _ := g.mem.GetNotices(ctx); len(n.Items) != 15 || !n.FetchedAt.Equal(now.Add(time.Hour)) {
		t.Errorf("the cache was overwritten: %+v", n)
	}
}

func TestHandleEventShapes(t *testing.T) {
	g := newRig(t, true)
	ctx := context.Background()
	for name, ev := range map[string]string{
		"weather": `{"job":"weather"}`,
		"smat":    `{"job":"smat"}`,
	} {
		if err := g.r.Handle(ctx, json.RawMessage(ev)); err != nil {
			t.Errorf("%s: %v", name, err)
		}
	}
	if g.wCalls.Load() != 1 || g.sCalls.Load() != 1 {
		t.Errorf("calls: weather %d, smat %d", g.wCalls.Load(), g.sCalls.Load())
	}
	// A manual invoke with any other event runs everything (guards apply).
	g.clock = now.Add(2 * time.Hour)
	if err := g.r.Handle(ctx, json.RawMessage(`{"detail-type":"Scheduled Event"}`)); err != nil {
		t.Fatal(err)
	}
	if g.wCalls.Load() != 2 || g.sCalls.Load() != 2 {
		t.Errorf("calls: weather %d, smat %d", g.wCalls.Load(), g.sCalls.Load())
	}
	if err := g.r.Handle(ctx, json.RawMessage(`{"job":"nope"}`)); err == nil {
		t.Error("an unknown job must fail loudly")
	}
	if err := g.r.Handle(ctx, nil); err != nil {
		t.Errorf("empty event: %v", err)
	}
}

func TestStoreFailureIsReported(t *testing.T) {
	g := newRig(t, true)
	g.mem.Err = store.ErrUnavailable
	if err := g.r.Run(context.Background(), ""); err == nil {
		t.Error("store failure must be reported")
	}
	if g.wCalls.Load() != 0 || g.sCalls.Load() != 0 {
		t.Error("no upstream request without a readable cache")
	}
}
