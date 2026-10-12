package api

import (
	"context"
	"encoding/json"
	"strings"
	"testing"
	"time"

	"github.com/pedro-santiago/toret/backend/internal/store"
)

func f64(v float64) *float64 { return &v }

func weatherAt(fetched time.Time) store.Weather {
	return store.Weather{
		TemperatureC: 24.1, ApparentTemperatureC: 26.3, RelativeHumidityPercent: 48,
		ApparentTemperatureMaxTodayC: f64(29.5),
		ObservedAt:                   fetched.Add(-11 * time.Minute), FetchedAt: fetched,
	}
}

func notices(fetched time.Time) store.Notices {
	return store.Notices{FetchedAt: fetched, Items: []store.Notice{{
		ID: "a1b2c3d4e5f6", Kind: "waterWorks", Street: "Corso Vittorio Emanuele II", FountainIDs: []string{"421310659"},
		Match: "street", StartedOn: "2026-10-05", PlannedEnd: "2026-10-23", Source: "SMAT S.p.A., Mappa Cantieri", FetchedAt: fetched,
	}, {
		ID: "b1b2c3d4e5f6", Kind: "fountainWorks", Street: "Via Nowhere", Match: "street", StartedOn: "2026-10-01",
		Source: "SMAT S.p.A., Mappa Cantieri", FetchedAt: fetched,
	}}}
}

func TestConditionsEmpty(t *testing.T) {
	e := newEnv(t)
	r := e.get("/v1/conditions", nil, nil)
	if r.StatusCode != 200 || r.Body != `{"weather":null,"notices":{"enabled":false,"items":[]}}` {
		t.Errorf("empty: %d %s", r.StatusCode, r.Body)
	}
	if r.Headers["Cache-Control"] != "public, max-age=300" || r.Headers["ETag"] == "" {
		t.Errorf("headers: %v", r.Headers)
	}
	if e.get("/v1/conditions", nil, map[string]string{"If-None-Match": r.Headers["ETag"]}).StatusCode != 304 {
		t.Error("conditions etag")
	}
}

func TestConditionsWeather(t *testing.T) {
	e := newEnv(t)
	fetched := epoch.Add(-12 * time.Minute)
	e.mem.PutWeather(context.Background(), weatherAt(fetched))
	r := e.get("/v1/conditions", nil, nil)
	want := `{"weather":{"temperatureC":24.1,"apparentTemperatureC":26.3,"relativeHumidityPercent":48,"apparentTemperatureMaxTodayC":29.5,` +
		`"observedAt":"2026-10-12T11:37:00Z","fetchedAt":"2026-10-12T11:48:00Z","attribution":"Weather data by Open-Meteo.com",` +
		`"licence":"CC BY 4.0","licenceURL":"https://creativecommons.org/licenses/by/4.0/","sourceURL":"https://open-meteo.com/"},` +
		`"notices":{"enabled":false,"items":[]}}`
	if r.Body != want {
		t.Errorf("weather\n got %s\nwant %s", r.Body, want)
	}

	// The daily maximum is omitted when there is none.
	w := weatherAt(fetched)
	w.ApparentTemperatureMaxTodayC = nil
	e.mem.PutWeather(context.Background(), w)
	if b := e.get("/v1/conditions", nil, nil).Body; strings.Contains(b, "apparentTemperatureMaxTodayC") {
		t.Errorf("daily max should be omitted: %s", b)
	}

	// Six hours is the limit: exactly six is shown, a second more is nothing.
	e.mem.PutWeather(context.Background(), weatherAt(epoch.Add(-6*time.Hour)))
	if b := e.get("/v1/conditions", nil, nil).Body; !strings.HasPrefix(b, `{"weather":{`) {
		t.Errorf("6 h old: %s", b)
	}
	e.mem.PutWeather(context.Background(), weatherAt(epoch.Add(-6*time.Hour-time.Second)))
	if b := e.get("/v1/conditions", nil, nil).Body; !strings.HasPrefix(b, `{"weather":null`) {
		t.Errorf("stale weather must be null: %s", b)
	}
}

func TestConditionsNotices(t *testing.T) {
	fetched := epoch.Add(-20 * time.Minute)
	e := newEnv(t, func(c *Config) { c.SMATEnabled = true })
	ctx := context.Background()

	// Enabled but never fetched: no data, not "no works".
	r := e.get("/v1/conditions", nil, nil)
	if want := `{"weather":null,"notices":{"enabled":true,"items":[]}}`; r.Body != want {
		t.Errorf("never fetched: %s", r.Body)
	}

	e.mem.PutNotices(ctx, notices(fetched))
	r = e.get("/v1/conditions", nil, nil)
	want := `{"weather":null,"notices":{"enabled":true,"fetchedAt":"2026-10-12T11:40:00Z","items":[` +
		`{"id":"a1b2c3d4e5f6","kind":"waterWorks","street":"Corso Vittorio Emanuele II","fountainIDs":["421310659"],"match":"street","startedOn":"2026-10-05","plannedEnd":"2026-10-23","source":"SMAT S.p.A., Mappa Cantieri","fetchedAt":"2026-10-12T11:40:00Z"},` +
		`{"id":"b1b2c3d4e5f6","kind":"fountainWorks","street":"Via Nowhere","fountainIDs":[],"match":"street","startedOn":"2026-10-01","source":"SMAT S.p.A., Mappa Cantieri","fetchedAt":"2026-10-12T11:40:00Z"}]}}`
	if r.Body != want {
		t.Errorf("notices\n got %s\nwant %s", r.Body, want)
	}

	// Older than six hours: no data again.
	e.mem.PutNotices(ctx, notices(epoch.Add(-6*time.Hour-time.Second)))
	if b := e.get("/v1/conditions", nil, nil).Body; b != `{"weather":null,"notices":{"enabled":true,"items":[]}}` {
		t.Errorf("stale notices: %s", b)
	}

	// A successful ingest with no works is "fetched, none": fetchedAt and [].
	e.mem.PutNotices(ctx, store.Notices{FetchedAt: fetched})
	if b := e.get("/v1/conditions", nil, nil).Body; b != `{"weather":null,"notices":{"enabled":true,"fetchedAt":"2026-10-12T11:40:00Z","items":[]}}` {
		t.Errorf("no works: %s", b)
	}

	// SMAT_ENABLED=false hides the feature entirely, cache or not, and the
	// store is not even read.
	off := newEnv(t)
	off.mem.PutNotices(ctx, notices(fetched))
	r = off.get("/v1/conditions", nil, nil)
	if r.Body != `{"weather":null,"notices":{"enabled":false,"items":[]}}` || off.mem.Calls["GetNotices"] != 0 {
		t.Errorf("disabled: %s (reads: %d)", r.Body, off.mem.Calls["GetNotices"])
	}
}

// There is no status, state or availability member anywhere in /v1/conditions,
// and no water word in any key (api.md section 1).
func TestConditionsNeverSayAWaterState(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.SMATEnabled = true })
	e.mem.PutWeather(context.Background(), weatherAt(epoch.Add(-time.Minute)))
	e.mem.PutNotices(context.Background(), notices(epoch.Add(-time.Minute)))
	var walk func(v any, path string)
	walk = func(v any, path string) {
		switch v := v.(type) {
		case map[string]any:
			for k, child := range v {
				switch strings.ToLower(k) {
				case "status", "state", "dry", "off", "running", "available", "availability", "flowing", "broken":
					t.Errorf("member %q at %s", k, path)
				}
				walk(child, path+"."+k)
			}
		case []any:
			for _, child := range v {
				walk(child, path+"[]")
			}
		}
	}
	var body any
	json.Unmarshal(plain(t, e.get("/v1/conditions", nil, nil)), &body)
	walk(body, "$")
}

func TestConditionsStoreFailure(t *testing.T) {
	e := newEnv(t, func(c *Config) { c.SMATEnabled = true })
	e.mem.Err = store.ErrUnavailable
	if r := e.get("/v1/conditions", nil, nil); r.StatusCode != 503 {
		t.Errorf("status %d", r.StatusCode)
	}
}
