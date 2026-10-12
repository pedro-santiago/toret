// Package weather fetches and parses the Open-Meteo forecast API for Turin.
//
// Weather data by Open-Meteo.com (CC BY 4.0). Anonymous use is limited to
// non-commercial purposes and one refresh per 15 minutes at most.
package weather

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"math"
	"net/http"
	"time"

	"github.com/pedro-santiago/toret/backend/internal/store"
)

// The constants /v1/conditions sends so the licence text lives in one place.
const (
	Attribution = "Weather data by Open-Meteo.com"
	Licence     = "CC BY 4.0"
	LicenceURL  = "https://creativecommons.org/licenses/by/4.0/"
	SourceURL   = "https://open-meteo.com/"

	URL = "https://api.open-meteo.com/v1/forecast?latitude=45.07&longitude=7.69" +
		"&current=temperature_2m,apparent_temperature,relative_humidity_2m" +
		"&daily=apparent_temperature_max&timezone=Europe/Rome"

	// MinInterval is the shortest time between two fetches (Open-Meteo's rule).
	MinInterval = 15 * time.Minute
)

type response struct {
	UTCOffsetSeconds *int `json:"utc_offset_seconds"`
	Current          struct {
		Time        string   `json:"time"`
		Temperature *float64 `json:"temperature_2m"`
		Apparent    *float64 `json:"apparent_temperature"`
		Humidity    *float64 `json:"relative_humidity_2m"`
	} `json:"current"`
	Daily struct {
		ApparentMax []*float64 `json:"apparent_temperature_max"`
	} `json:"daily"`
}

// Parse reads an Open-Meteo response. current.time is local Europe/Rome time
// without an offset; utc_offset_seconds in the same response converts it, so
// no time zone database is needed. The daily maximum is optional.
func Parse(body []byte, fetchedAt time.Time) (store.Weather, error) {
	var r response
	if err := json.Unmarshal(body, &r); err != nil {
		return store.Weather{}, fmt.Errorf("weather: %w", err)
	}
	if r.Current.Temperature == nil || r.Current.Apparent == nil || r.Current.Humidity == nil || r.UTCOffsetSeconds == nil {
		return store.Weather{}, errors.New("weather: response lacks current values")
	}
	local, err := time.Parse("2006-01-02T15:04", r.Current.Time)
	if err != nil {
		return store.Weather{}, fmt.Errorf("weather: current.time: %w", err)
	}
	w := store.Weather{
		TemperatureC:            *r.Current.Temperature,
		ApparentTemperatureC:    *r.Current.Apparent,
		RelativeHumidityPercent: int(math.Round(*r.Current.Humidity)),
		ObservedAt:              local.Add(-time.Duration(*r.UTCOffsetSeconds) * time.Second).UTC(),
		FetchedAt:               fetchedAt.UTC().Truncate(time.Second),
	}
	if len(r.Daily.ApparentMax) > 0 && r.Daily.ApparentMax[0] != nil {
		w.ApparentTemperatureMaxTodayC = r.Daily.ApparentMax[0]
	}
	return w, nil
}

// Client fetches the forecast.
type Client struct {
	HTTP *http.Client
	URL  string // defaults to URL
}

// Fetch calls Open-Meteo once.
func (c Client) Fetch(ctx context.Context, now time.Time) (store.Weather, error) {
	url := c.URL
	if url == "" {
		url = URL
	}
	hc := c.HTTP
	if hc == nil {
		hc = &http.Client{Timeout: 15 * time.Second}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return store.Weather{}, err
	}
	req.Header.Set("User-Agent", "toret-ingest (+https://github.com/pedro-santiago/toret)")
	res, err := hc.Do(req)
	if err != nil {
		return store.Weather{}, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return store.Weather{}, fmt.Errorf("weather: upstream status %d", res.StatusCode)
	}
	body, err := io.ReadAll(io.LimitReader(res.Body, 1<<20))
	if err != nil {
		return store.Weather{}, err
	}
	return Parse(body, now)
}
