// Package ingest is the scheduled job: it refreshes the weather cache every 15
// minutes and, only when SMAT_ENABLED is true, the works notices every hour.
// The API Lambda never calls an upstream; it reads what this writes.
package ingest

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"log/slog"
	"time"

	"github.com/pedro-santiago/toret/backend/internal/catalogue"
	"github.com/pedro-santiago/toret/backend/internal/smat"
	"github.com/pedro-santiago/toret/backend/internal/store"
	"github.com/pedro-santiago/toret/backend/internal/weather"
)

// Jobs, as named in the schedule's constant input {"job": "..."}.
const (
	JobWeather = "weather"
	JobSMAT    = "smat"
)

// Slack under the schedule period, so a run that fires a few seconds early is
// not skipped, while a duplicate invocation is.
const (
	weatherGuard = weather.MinInterval - time.Minute
	smatGuard    = smat.MinInterval - 5*time.Minute
)

// Runner holds what a run needs.
type Runner struct {
	Store       store.Store
	Catalogue   *catalogue.Catalogue
	Weather     weather.Client
	SMAT        smat.Client
	SMATEnabled bool
	Now         func() time.Time
	Log         *slog.Logger
}

// Handle is the Lambda entry point. The event is the schedule's constant input;
// anything else (a manual test invoke) runs every job.
func (r *Runner) Handle(ctx context.Context, raw json.RawMessage) error {
	var ev struct {
		Job string `json:"job"`
	}
	_ = json.Unmarshal(raw, &ev)
	return r.Run(ctx, ev.Job)
}

// Run runs one job, or all of them when job is empty. A failure is returned
// (so the invocation shows up in the Errors metric) but never overwrites a
// good cache.
func (r *Runner) Run(ctx context.Context, job string) error {
	var errs []error
	switch job {
	case JobWeather:
		errs = append(errs, r.weather(ctx))
	case JobSMAT:
		errs = append(errs, r.smat(ctx))
	case "":
		errs = append(errs, r.weather(ctx), r.smat(ctx))
	default:
		return fmt.Errorf("ingest: unknown job %q", job)
	}
	return errors.Join(errs...)
}

func (r *Runner) weather(ctx context.Context) error {
	now := r.Now().UTC()
	cached, err := r.Store.GetWeather(ctx)
	if err != nil {
		return fmt.Errorf("weather: read cache: %w", err)
	}
	if cached != nil && now.Sub(cached.FetchedAt) < weatherGuard && !now.Before(cached.FetchedAt) {
		r.Log.Info("weather: fresh, skipped", "fetchedAt", cached.FetchedAt)
		return nil
	}
	w, err := r.Weather.Fetch(ctx, now)
	if err != nil {
		return fmt.Errorf("weather: %w", err)
	}
	if err := r.Store.PutWeather(ctx, w); err != nil {
		return fmt.Errorf("weather: write cache: %w", err)
	}
	r.Log.Info("weather: refreshed", "observedAt", w.ObservedAt)
	return nil
}

func (r *Runner) smat(ctx context.Context) error {
	if !r.SMATEnabled {
		return nil // no read, no request: the flag is off
	}
	now := r.Now().UTC()
	cached, err := r.Store.GetNotices(ctx)
	if err != nil {
		return fmt.Errorf("smat: read cache: %w", err)
	}
	if cached != nil && now.Sub(cached.FetchedAt) < smatGuard && !now.Before(cached.FetchedAt) {
		r.Log.Info("smat: fresh, skipped", "fetchedAt", cached.FetchedAt)
		return nil
	}
	body, err := r.SMAT.Fetch(ctx)
	if err != nil {
		return fmt.Errorf("smat: %w", err)
	}
	items, err := smat.Parse(body, r.Catalogue, now)
	if err != nil {
		return err
	}
	if err := r.Store.PutNotices(ctx, store.Notices{FetchedAt: now.Truncate(time.Second), Items: items}); err != nil {
		return fmt.Errorf("smat: write cache: %w", err)
	}
	r.Log.Info("smat: refreshed", "notices", len(items))
	return nil
}
