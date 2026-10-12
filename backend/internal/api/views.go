package api

import (
	"bytes"
	"encoding/json"
	"io"

	"github.com/pedro-santiago/toret/backend/internal/httpx"
	"github.com/pedro-santiago/toret/backend/internal/store"
	"github.com/pedro-santiago/toret/backend/internal/weather"
)

// The /v1/conditions body (api.md section 6.7). There is no status, state or
// availability member anywhere in it, and there never is one.

type conditionsView struct {
	Weather *weatherView `json:"weather"`
	Notices noticesView  `json:"notices"`
}

type weatherView struct {
	TemperatureC                 float64  `json:"temperatureC"`
	ApparentTemperatureC         float64  `json:"apparentTemperatureC"`
	RelativeHumidityPercent      int      `json:"relativeHumidityPercent"`
	ApparentTemperatureMaxTodayC *float64 `json:"apparentTemperatureMaxTodayC,omitempty"`
	ObservedAt                   string   `json:"observedAt"`
	FetchedAt                    string   `json:"fetchedAt"`
	Attribution                  string   `json:"attribution"`
	Licence                      string   `json:"licence"`
	LicenceURL                   string   `json:"licenceURL"`
	SourceURL                    string   `json:"sourceURL"`
}

type noticesView struct {
	Enabled   bool         `json:"enabled"`
	FetchedAt string       `json:"fetchedAt,omitempty"`
	Items     []noticeView `json:"items"`
}

type noticeView struct {
	ID          string   `json:"id"`
	Kind        string   `json:"kind"`
	Street      string   `json:"street"`
	FountainIDs []string `json:"fountainIDs"`
	Match       string   `json:"match"`
	StartedOn   string   `json:"startedOn"`
	PlannedEnd  string   `json:"plannedEnd,omitempty"`
	Source      string   `json:"source"`
	FetchedAt   string   `json:"fetchedAt"`
}

func weatherOf(w store.Weather) *weatherView {
	return &weatherView{
		TemperatureC: w.TemperatureC, ApparentTemperatureC: w.ApparentTemperatureC,
		RelativeHumidityPercent: w.RelativeHumidityPercent, ApparentTemperatureMaxTodayC: w.ApparentTemperatureMaxTodayC,
		ObservedAt: httpx.FormatTime(w.ObservedAt), FetchedAt: httpx.FormatTime(w.FetchedAt),
		Attribution: weather.Attribution, Licence: weather.Licence, LicenceURL: weather.LicenceURL, SourceURL: weather.SourceURL,
	}
}

func noticesOf(items []store.Notice) []noticeView {
	out := make([]noticeView, len(items))
	for i, n := range items {
		ids := n.FountainIDs
		if ids == nil {
			ids = []string{}
		}
		out[i] = noticeView{
			ID: n.ID, Kind: n.Kind, Street: n.Street, FountainIDs: ids, Match: n.Match,
			StartedOn: n.StartedOn, PlannedEnd: n.PlannedEnd, Source: n.Source, FetchedAt: httpx.FormatTime(n.FetchedAt),
		}
	}
	return out
}

// decodeObject decodes exactly one JSON object and nothing after it.
func decodeObject(b []byte, v any) error {
	dec := json.NewDecoder(bytes.NewReader(b))
	if err := dec.Decode(v); err != nil {
		return err
	}
	if dec.Decode(&struct{}{}) != io.EOF {
		return io.ErrUnexpectedEOF
	}
	return nil
}
