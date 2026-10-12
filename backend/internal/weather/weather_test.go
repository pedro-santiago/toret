package weather

import (
	"context"
	"net/http"
	"net/http/httptest"
	"os"
	"testing"
	"time"
)

var fetched = time.Date(2026, 10, 12, 16, 5, 7, 900_000_000, time.UTC)

// testdata/open-meteo.json is one real response (fetched 2026-10-12).
func TestParseFixture(t *testing.T) {
	body, err := os.ReadFile("testdata/open-meteo.json")
	if err != nil {
		t.Fatal(err)
	}
	w, err := Parse(body, fetched)
	if err != nil {
		t.Fatal(err)
	}
	if w.TemperatureC != 20.8 || w.ApparentTemperatureC != 19.9 || w.RelativeHumidityPercent != 51 {
		t.Errorf("values = %+v", w)
	}
	if w.ApparentTemperatureMaxTodayC == nil || *w.ApparentTemperatureMaxTodayC != 20.6 {
		t.Errorf("daily max = %v", w.ApparentTemperatureMaxTodayC)
	}
	// 18:00 Rome local time at UTC+2 is 16:00Z.
	if want := time.Date(2026, 10, 12, 16, 0, 0, 0, time.UTC); !w.ObservedAt.Equal(want) {
		t.Errorf("observedAt = %s, want %s", w.ObservedAt, want)
	}
	if want := time.Date(2026, 10, 12, 16, 5, 7, 0, time.UTC); !w.FetchedAt.Equal(want) {
		t.Errorf("fetchedAt = %s, want %s (whole seconds)", w.FetchedAt, want)
	}
}

func TestParseVariants(t *testing.T) {
	for _, tc := range []struct {
		name, body string
		ok         bool
		check      func(t *testing.T, observed time.Time, dailyMax *float64, humidity int)
	}{
		{"winter offset", `{"utc_offset_seconds":3600,"current":{"time":"2026-01-05T08:30","temperature_2m":-1.5,"apparent_temperature":-4,"relative_humidity_2m":90.4},"daily":{"apparent_temperature_max":[2.5]}}`, true,
			func(t *testing.T, o time.Time, m *float64, h int) {
				if !o.Equal(time.Date(2026, 1, 5, 7, 30, 0, 0, time.UTC)) || h != 90 || *m != 2.5 {
					t.Errorf("observed %s humidity %d max %v", o, h, *m)
				}
			}},
		{"daily empty", `{"utc_offset_seconds":7200,"current":{"time":"2026-07-05T08:30","temperature_2m":30,"apparent_temperature":33,"relative_humidity_2m":40},"daily":{"apparent_temperature_max":[]}}`, true,
			func(t *testing.T, _ time.Time, m *float64, _ int) {
				if m != nil {
					t.Error("daily max must be omitted")
				}
			}},
		{"daily null", `{"utc_offset_seconds":7200,"current":{"time":"2026-07-05T08:30","temperature_2m":30,"apparent_temperature":33,"relative_humidity_2m":40},"daily":{"apparent_temperature_max":[null]}}`, true,
			func(t *testing.T, _ time.Time, m *float64, _ int) {
				if m != nil {
					t.Error("daily max must be omitted")
				}
			}},
		{"no daily", `{"utc_offset_seconds":7200,"current":{"time":"2026-07-05T08:30","temperature_2m":30,"apparent_temperature":33,"relative_humidity_2m":40}}`, true,
			func(t *testing.T, _ time.Time, m *float64, _ int) {
				if m != nil {
					t.Error("daily max must be omitted")
				}
			}},
		{"missing humidity", `{"utc_offset_seconds":7200,"current":{"time":"2026-07-05T08:30","temperature_2m":30,"apparent_temperature":33}}`, false, nil},
		{"null temperature", `{"utc_offset_seconds":7200,"current":{"time":"2026-07-05T08:30","temperature_2m":null,"apparent_temperature":33,"relative_humidity_2m":40}}`, false, nil},
		{"missing offset", `{"current":{"time":"2026-07-05T08:30","temperature_2m":30,"apparent_temperature":33,"relative_humidity_2m":40}}`, false, nil},
		{"bad time", `{"utc_offset_seconds":7200,"current":{"time":"noon","temperature_2m":30,"apparent_temperature":33,"relative_humidity_2m":40}}`, false, nil},
		{"error body", `{"error":true,"reason":"Latitude must be in range of -90 to 90°."}`, false, nil},
		{"not json", `<html>`, false, nil},
	} {
		w, err := Parse([]byte(tc.body), fetched)
		if (err == nil) != tc.ok {
			t.Errorf("%s: err = %v", tc.name, err)
			continue
		}
		if tc.ok && tc.check != nil {
			tc.check(t, w.ObservedAt, w.ApparentTemperatureMaxTodayC, w.RelativeHumidityPercent)
		}
	}
}

func TestFetch(t *testing.T) {
	body, _ := os.ReadFile("testdata/open-meteo.json")
	var gotUA string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		gotUA = r.Header.Get("User-Agent")
		if r.URL.Path == "/down" {
			http.Error(w, "no", http.StatusServiceUnavailable)
			return
		}
		w.Write(body)
	}))
	defer srv.Close()

	w, err := Client{URL: srv.URL + "/ok"}.Fetch(context.Background(), fetched)
	if err != nil || w.TemperatureC != 20.8 {
		t.Fatalf("Fetch = %+v, %v", w, err)
	}
	if gotUA == "" {
		t.Error("a User-Agent must identify the app")
	}
	if _, err := (Client{URL: srv.URL + "/down"}).Fetch(context.Background(), fetched); err == nil {
		t.Error("a 503 must be an error")
	}
}
