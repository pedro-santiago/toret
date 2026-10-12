// Package api is the HTTP layer of the Lambda: routing on API Gateway's route
// key, the checks of docs/backend/api.md in their documented order, and the
// shape of every response. It talks to storage only through store.Store.
package api

import (
	"context"
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"mime"
	"strconv"
	"sync"
	"time"

	"github.com/aws/aws-lambda-go/events"

	"github.com/pedro-santiago/toret/backend/internal/catalogue"
	"github.com/pedro-santiago/toret/backend/internal/handle"
	"github.com/pedro-santiago/toret/backend/internal/httpx"
	"github.com/pedro-santiago/toret/backend/internal/ratelimit"
	"github.com/pedro-santiago/toret/backend/internal/reports"
	"github.com/pedro-santiago/toret/backend/internal/store"
)

// Limits of api.md sections 4 and 6.
const (
	MaxBody = 4 << 10

	feedWindow       = 30 * 24 * time.Hour
	conditionsMaxAge = 6 * time.Hour

	// summaryReadCap is how many reports one summaries read looks at. The global
	// write ceiling (ratelimit.Config.GlobalPerHour) times the hourly windows a
	// 36 h read touches stays under it, so a flood cannot push genuine reports
	// out of the summaries (a test pins the arithmetic).
	summaryReadCap   = 10000
	summaryCacheTime = 20 * time.Second

	// Feed and per-fountain lists are kept this long per warm Lambda; the client
	// already tolerates 60 s of read-after-write lag (api.md 5.1). A write
	// through the same container clears them at once.
	listCacheTime = 10 * time.Second
	listCacheMax  = 128
	feedMax       = 200 // the largest ?limit= of a feed
	fountainMax   = 100 // the largest ?limit= of a fountain list
)

// Config wires a Handler. Store, Catalogue and Pepper are required.
type Config struct {
	Store     store.Store
	Catalogue *catalogue.Catalogue
	// Pepper returns the HMAC key; it is called lazily and its result kept,
	// so /v1/health works without it.
	Pepper      func(context.Context) ([]byte, error)
	SMATEnabled bool
	Version     string
	Limits      ratelimit.Config // zero value: ratelimit.Defaults
	Now         func() time.Time // default time.Now
	Logger      *slog.Logger     // default: discard
}

// Handler serves the API.
type Handler struct {
	cfg     Config
	limiter *ratelimit.Limiter
	log     *slog.Logger

	pepperMu sync.Mutex
	pepper   []byte

	sumMu   sync.Mutex
	sumAt   time.Time
	sumBody []byte

	listMu    sync.Mutex
	listCache map[string]listEntry
}

// listEntry is a list read at its largest limit; requests slice it.
type listEntry struct {
	at   time.Time
	recs []store.Record
}

// New builds a Handler.
func New(cfg Config) *Handler {
	if cfg.Now == nil {
		cfg.Now = time.Now
	}
	if cfg.Version == "" {
		cfg.Version = "1.0.0"
	}
	log := cfg.Logger
	if log == nil {
		log = slog.New(slog.NewTextHandler(io.Discard, nil))
	}
	l := ratelimit.New(cfg.Store, func() time.Time { return cfg.Now().UTC() })
	if cfg.Limits != (ratelimit.Config{}) {
		l.Config = cfg.Limits
	}
	return &Handler{cfg: cfg, limiter: l, log: log, listCache: map[string]listEntry{}}
}

func (h *Handler) now() time.Time { return h.cfg.Now().UTC() }

// Handle is the Lambda entry point. It never returns an error: every failure
// is a response.
func (h *Handler) Handle(ctx context.Context, req events.APIGatewayV2HTTPRequest) (resp events.APIGatewayV2HTTPResponse, _ error) {
	start := time.Now()
	reqID := req.RequestContext.RequestID
	lang := httpx.Lang(httpx.Header(req.Headers, "Accept-Language"))
	gzipOK := httpx.AcceptsGzip(httpx.Header(req.Headers, "Accept-Encoding"))

	var reply httpx.Reply
	var failure error
	func() {
		defer func() {
			if p := recover(); p != nil {
				failure = fmt.Errorf("panic: %v", p)
				reply = httpx.Fail(500, "internal", "", "")
			}
		}()
		reply, failure = h.dispatch(ctx, req)
	}()
	resp = httpx.Finish(reply, reqID, lang, gzipOK)

	// Never the raw install token or source address.
	attrs := []any{
		"route", req.RouteKey, "status", resp.StatusCode, "requestId", reqID,
		"client", logClient(httpx.Header(req.Headers, "X-Toret-Client")), "ms", time.Since(start).Milliseconds(),
	}
	if reply.Err != nil {
		attrs = append(attrs, "code", reply.Err.Code, "reason", reply.Err.Reason)
	}
	if failure != nil {
		h.log.Error("request failed", append(attrs, "err", failure.Error())...)
	} else {
		h.log.Info("request", attrs...)
	}
	return resp, nil
}

// logClient makes X-Toret-Client safe to log: it is caller controlled and as
// long as a header may be, so only its first 32 characters of [0-9A-Za-z.+_-]
// are kept ("1.0.0+42" passes untouched).
func logClient(v string) string {
	const max = 32
	out := make([]byte, 0, max)
	for i := 0; i < len(v) && len(out) < max; i++ {
		switch c := v[i]; {
		case c >= '0' && c <= '9', c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c == '.', c == '+', c == '_', c == '-':
			out = append(out, c)
		}
	}
	return string(out)
}

func (h *Handler) dispatch(ctx context.Context, req events.APIGatewayV2HTTPRequest) (httpx.Reply, error) {
	inm := httpx.Header(req.Headers, "If-None-Match")
	switch req.RouteKey {
	case "GET /v1/health":
		return httpx.JSON(200, map[string]any{
			"status": "ok", "version": h.cfg.Version, "catalogue": h.cfg.Catalogue.Len(),
		}), nil
	case "GET /v1/reports":
		return h.listFeed(ctx, req, inm)
	case "GET /v1/fountains/{id}/reports":
		return h.listFountain(ctx, req, inm)
	case "GET /v1/summaries":
		return h.summaries(ctx, inm)
	case "GET /v1/conditions":
		return h.conditions(ctx, inm)
	case "POST /v1/reports":
		return h.postReport(ctx, req)
	case "DELETE /v1/reports/{id}":
		return h.deleteReport(ctx, req)
	case "POST /v1/reports/{id}/flag":
		return h.flagReport(ctx, req)
	}
	// API Gateway answers unknown routes itself; this is only reached by a
	// route added to the template and not here.
	return httpx.Fail(404, "bad_request", "", ""), nil
}

// ---- helpers -----------------------------------------------------------------

// internalError maps a store failure: retryable ones are 503, the rest 500.
func internalError(err error) (httpx.Reply, error) {
	if errors.Is(err, store.ErrUnavailable) {
		return httpx.Fail(503, "unavailable", "", "").With("Retry-After", "5"), err
	}
	return httpx.Fail(500, "internal", "", ""), err
}

func (h *Handler) secret(ctx context.Context) ([]byte, error) {
	h.pepperMu.Lock()
	defer h.pepperMu.Unlock()
	if h.pepper != nil {
		return h.pepper, nil
	}
	p, err := h.cfg.Pepper(ctx)
	if err != nil {
		return nil, fmt.Errorf("%w: pepper: %v", store.ErrUnavailable, err)
	}
	if len(p) == 0 {
		return nil, errors.New("pepper is empty")
	}
	h.pepper = p
	return p, nil
}

// body returns the request body, decoded from base64 when API Gateway encoded
// it, or a 413. The cap applies to the decoded bytes.
func body(req events.APIGatewayV2HTTPRequest) ([]byte, *httpx.Reply) {
	tooLarge := httpx.Fail(413, "body_too_large", "", "")
	raw := req.Body
	if req.IsBase64Encoded {
		if base64.StdEncoding.DecodedLen(len(raw)) > MaxBody+2 {
			return nil, &tooLarge
		}
		dec, err := base64.StdEncoding.DecodeString(raw)
		if err != nil {
			bad := httpx.Fail(400, "bad_request", "", "")
			return nil, &bad
		}
		if len(dec) > MaxBody {
			return nil, &tooLarge
		}
		return dec, nil
	}
	if len(raw) > MaxBody {
		return nil, &tooLarge
	}
	return []byte(raw), nil
}

// jsonBody applies the size and content-type checks of a write with a body.
func jsonBody(req events.APIGatewayV2HTTPRequest) ([]byte, *httpx.Reply) {
	b, rep := body(req)
	if rep != nil {
		return nil, rep
	}
	media, _, err := mime.ParseMediaType(httpx.Header(req.Headers, "Content-Type"))
	if err != nil || media != "application/json" {
		r := httpx.Fail(415, "unsupported_media_type", "", "")
		return nil, &r
	}
	return b, nil
}

// install reads X-Toret-Install; it is used byte for byte.
func install(req events.APIGatewayV2HTTPRequest) (string, *httpx.Reply) {
	token := httpx.Header(req.Headers, "X-Toret-Install")
	if !handle.ValidToken(token) {
		r := httpx.Fail(401, "install_required", "", "")
		return "", &r
	}
	return token, nil
}

// writer identifies the caller of a write.
type writer struct {
	token, installHash, ipHash string
}

// identify computes the hashes of a write. It needs the pepper, so it comes
// after every check that does not.
func (h *Handler) identify(ctx context.Context, req events.APIGatewayV2HTTPRequest, token string) (writer, error) {
	pepper, err := h.secret(ctx)
	if err != nil {
		return writer{}, err
	}
	return writer{token, handle.InstallHash(pepper, token), handle.IPHash(pepper, req.RequestContext.HTTP.SourceIP)}, nil
}

func rateHeaders(r httpx.Reply, res ratelimit.Result) httpx.Reply {
	return r.
		With("RateLimit-Limit", strconv.Itoa(res.Limit)).
		With("RateLimit-Remaining", strconv.Itoa(res.Remaining)).
		With("RateLimit-Reset", strconv.Itoa(res.Reset))
}

func limited(res ratelimit.Result) httpx.Reply {
	return rateHeaders(httpx.Fail(429, "rate_limited", "", res.Scope), res).
		With("Retry-After", strconv.Itoa(res.RetryAfter))
}

// admit runs the ban check and the hourly write buckets shared by every write.
// It does not touch the global ceiling: that is counted last, by global.
func (h *Handler) admit(ctx context.Context, w writer) (ratelimit.Result, *httpx.Reply, error) {
	banned, err := h.cfg.Store.Banned(ctx, w.installHash, w.ipHash)
	if err != nil {
		r, e := internalError(err)
		return ratelimit.Result{}, &r, e
	}
	if banned {
		r := httpx.Fail(403, "forbidden", "", "")
		return ratelimit.Result{}, &r, nil
	}
	res, err := h.limiter.Write(ctx, w.installHash, w.ipHash)
	if err != nil {
		r, e := internalError(err)
		return res, &r, e
	}
	if !res.Allowed {
		r := limited(res)
		return res, &r, nil
	}
	return res, nil, nil
}

// global counts a write that passed every per-caller gate against the ceiling
// shared by all callers.
func (h *Handler) global(ctx context.Context, res ratelimit.Result) (ratelimit.Result, *httpx.Reply, error) {
	res, err := h.limiter.Global(ctx, res)
	if err != nil {
		r, e := internalError(err)
		return res, &r, e
	}
	if !res.Allowed {
		r := limited(res)
		return res, &r, nil
	}
	return res, nil, nil
}

// limit parses ?limit=; a value above max is clamped.
func limit(req events.APIGatewayV2HTTPRequest, def, max int) (int, bool) {
	v, present := req.QueryStringParameters["limit"]
	if !present {
		return def, true
	}
	if v == "" {
		return 0, false
	}
	for i := 0; i < len(v); i++ {
		if v[i] < '0' || v[i] > '9' {
			return 0, false
		}
	}
	n, err := strconv.ParseInt(v, 10, 32)
	if err != nil {
		// Only a range error can get here, and an absurd number is "large".
		return max, true
	}
	if n < 1 {
		return 0, false
	}
	return min(int(n), max), true
}

// ---- reads -------------------------------------------------------------------

func (h *Handler) listFeed(ctx context.Context, req events.APIGatewayV2HTTPRequest, inm string) (httpx.Reply, error) {
	n, ok := limit(req, 50, feedMax)
	if !ok {
		return httpx.Fail(400, "invalid_limit", "limit", ""), nil
	}
	recs, err := h.cachedList(ctx, "feed", func(now time.Time) ([]store.Record, error) {
		return h.cfg.Store.Feed(ctx, now.Add(-feedWindow), feedMax)
	})
	if err != nil {
		return internalError(err)
	}
	return reportList(recs[:min(n, len(recs))], inm), nil
}

func (h *Handler) listFountain(ctx context.Context, req events.APIGatewayV2HTTPRequest, inm string) (httpx.Reply, error) {
	id := req.PathParameters["id"]
	if !digits(id) {
		return httpx.Fail(400, "bad_request", "id", ""), nil
	}
	n, ok := limit(req, 40, fountainMax)
	if !ok {
		return httpx.Fail(400, "invalid_limit", "limit", ""), nil
	}
	if _, known := h.cfg.Catalogue.Get(id); !known {
		return httpx.Fail(404, "unknown_fountain", "id", ""), nil
	}
	recs, err := h.cachedList(ctx, "fountain:"+id, func(now time.Time) ([]store.Record, error) {
		return h.cfg.Store.Fountain(ctx, id, now.Add(-feedWindow), fountainMax)
	})
	if err != nil {
		return internalError(err)
	}
	return reportList(recs[:min(n, len(recs))], inm), nil
}

// cachedList returns the list under key from the warm container's cache, or
// reads it at the largest limit. A store failure is not cached.
func (h *Handler) cachedList(ctx context.Context, key string, read func(now time.Time) ([]store.Record, error)) ([]store.Record, error) {
	now := h.now()
	h.listMu.Lock()
	defer h.listMu.Unlock()
	if e, ok := h.listCache[key]; ok && !now.Before(e.at) && now.Sub(e.at) < listCacheTime {
		return e.recs, nil
	}
	recs, err := read(now)
	if err != nil {
		return nil, err
	}
	if len(h.listCache) >= listCacheMax {
		clear(h.listCache) // at most a few hundred fountains, and every entry is 10 s old at best
	}
	h.listCache[key] = listEntry{at: now, recs: recs}
	return recs, nil
}

// forgetLists drops the cached lists after a write through this container.
func (h *Handler) forgetLists() {
	h.listMu.Lock()
	clear(h.listCache)
	h.listMu.Unlock()
}

func digits(s string) bool {
	if len(s) == 0 || len(s) > 12 {
		return false
	}
	for i := 0; i < len(s); i++ {
		if s[i] < '0' || s[i] > '9' {
			return false
		}
	}
	return true
}

func reportList(recs []store.Record, inm string) httpx.Reply {
	r := httpx.JSON(200, map[string]any{"reports": reports.Views(recs)})
	return httpx.Cached(r.Body, "no-cache", inm)
}

func (h *Handler) summaries(ctx context.Context, inm string) (httpx.Reply, error) {
	now := h.now()
	h.sumMu.Lock()
	defer h.sumMu.Unlock()
	if h.sumBody == nil || now.Before(h.sumAt) || now.Sub(h.sumAt) >= summaryCacheTime {
		recs, err := h.cfg.Store.Feed(ctx, now.Add(-reports.Freshness), summaryReadCap)
		if err != nil {
			return internalError(err)
		}
		if len(recs) >= summaryReadCap {
			// Fountains whose reports lie beyond the newest summaryReadCap are
			// left out (they read as "no report", which fails safe).
			h.log.Warn("summaries truncated", "cap", summaryReadCap)
		}
		r := httpx.JSON(200, map[string]any{
			"windowHours": int(reports.Freshness / time.Hour),
			"summaries":   reports.Summarise(recs, now),
		})
		h.sumBody, h.sumAt = r.Body, now
	}
	return httpx.Cached(h.sumBody, "private, max-age=60", inm), nil
}

// ---- writes ------------------------------------------------------------------

func (h *Handler) postReport(ctx context.Context, req events.APIGatewayV2HTTPRequest) (httpx.Reply, error) {
	b, rep := jsonBody(req)
	if rep != nil {
		return *rep, nil
	}
	token, rep := install(req)
	if rep != nil {
		return *rep, nil
	}
	now := h.now()
	draft, rej := reports.Validate(b, h.cfg.Catalogue, now)
	if rej != nil {
		return httpx.Fail(rej.Status, rej.Code, rej.Field, rej.Reason), nil
	}
	w, err := h.identify(ctx, req, token)
	if err != nil {
		return internalError(err)
	}

	// Idempotency comes before the rate limit: a retry of a report that already
	// landed is a success, never a 429.
	existing, err := h.cfg.Store.GetReport(ctx, draft.ID)
	if err != nil {
		return internalError(err)
	}
	if existing != nil {
		return stored(existing, w.installHash), nil
	}

	res, stop, err := h.admit(ctx, w)
	if stop != nil {
		return *stop, err
	}
	if res, err = h.limiter.Fountain(ctx, res, w.installHash, w.ipHash, draft.FountainID); err != nil {
		return internalError(err)
	}
	if !res.Allowed {
		return limited(res), nil
	}
	if res, stop, err = h.global(ctx, res); stop != nil {
		return *stop, err
	}

	rec := draft.Record(handle.Author(token), w.installHash, now)
	created, err := h.cfg.Store.PutReport(ctx, rec)
	if err != nil {
		return internalError(err)
	}
	h.forgetLists()
	if !created {
		// Lost the race to a concurrent request with the same id.
		other, err := h.cfg.Store.GetReport(ctx, draft.ID)
		if err != nil {
			return internalError(err)
		}
		if other == nil {
			return httpx.Fail(503, "unavailable", "", "").With("Retry-After", "1"), nil
		}
		return stored(other, w.installHash), nil
	}
	return rateHeaders(httpx.JSON(201, reports.ViewOf(rec)), res), nil
}

// stored answers a POST whose id is already taken: the stored report for the
// same install, 409 for another.
func stored(rec *store.Record, installHash string) httpx.Reply {
	if rec.InstallHash != installHash {
		return httpx.Fail(409, "id_conflict", "id", "")
	}
	return httpx.JSON(200, reports.ViewOf(*rec))
}

func (h *Handler) deleteReport(ctx context.Context, req events.APIGatewayV2HTTPRequest) (httpx.Reply, error) {
	token, rep := install(req)
	if rep != nil {
		return *rep, nil
	}
	id, ok := reports.NormaliseID(req.PathParameters["id"])
	if !ok {
		return httpx.Fail(422, "invalid_id", "id", ""), nil
	}
	w, err := h.identify(ctx, req, token)
	if err != nil {
		return internalError(err)
	}
	res, stop, err := h.admit(ctx, w)
	if stop != nil {
		return *stop, err
	}
	if res, stop, err = h.global(ctx, res); stop != nil {
		return *stop, err
	}
	outcome, err := h.cfg.Store.DeleteReport(ctx, id, w.installHash)
	if err != nil {
		return internalError(err)
	}
	h.forgetLists()
	if outcome == store.NotOwner {
		return rateHeaders(httpx.Fail(403, "not_owner", "id", ""), res), nil
	}
	return rateHeaders(httpx.NoContent(), res), nil
}

func (h *Handler) flagReport(ctx context.Context, req events.APIGatewayV2HTTPRequest) (httpx.Reply, error) {
	b, rep := jsonBody(req)
	if rep != nil {
		return *rep, nil
	}
	token, rep := install(req)
	if rep != nil {
		return *rep, nil
	}
	id, ok := reports.NormaliseID(req.PathParameters["id"])
	if !ok {
		return httpx.Fail(422, "invalid_id", "id", ""), nil
	}
	reason, bad := flagReason(b)
	if bad != nil {
		return *bad, nil
	}
	w, err := h.identify(ctx, req, token)
	if err != nil {
		return internalError(err)
	}
	res, stop, err := h.admit(ctx, w)
	if stop != nil {
		return *stop, err
	}
	if res, stop, err = h.global(ctx, res); stop != nil {
		return *stop, err
	}
	// Whatever happens to the flag, the client's queue moves on with a 204.
	if _, err := h.cfg.Store.Flag(ctx, store.FlagRequest{
		ReportID: id, InstallHash: w.installHash, IPHash: w.ipHash, Reason: reason, Now: h.now(),
	}); err != nil {
		return internalError(err)
	}
	h.forgetLists() // a third flag hides the report
	return rateHeaders(httpx.NoContent(), res), nil
}

func flagReason(b []byte) (string, *httpx.Reply) {
	var in struct {
		Reason any `json:"reason"`
	}
	if err := decodeObject(b, &in); err != nil {
		r := httpx.Fail(400, "bad_request", "", "")
		return "", &r
	}
	reason, _ := in.Reason.(string)
	if !reports.FlagReasons[reason] {
		r := httpx.Fail(422, "invalid_reason", "reason", "")
		return "", &r
	}
	return reason, nil
}

// ---- conditions ----------------------------------------------------------------

func (h *Handler) conditions(ctx context.Context, inm string) (httpx.Reply, error) {
	now := h.now()
	out := conditionsView{Notices: noticesView{Enabled: h.cfg.SMATEnabled, Items: []noticeView{}}}

	w, err := h.cfg.Store.GetWeather(ctx)
	if err != nil {
		return internalError(err)
	}
	if w != nil && now.Sub(w.FetchedAt) <= conditionsMaxAge {
		out.Weather = weatherOf(*w)
	}
	if h.cfg.SMATEnabled {
		n, err := h.cfg.Store.GetNotices(ctx)
		if err != nil {
			return internalError(err)
		}
		// Older than six hours (or never fetched) is "no data", which is not
		// the same as "no works": fetchedAt is left out and the list is empty.
		if n != nil && now.Sub(n.FetchedAt) <= conditionsMaxAge {
			out.Notices.FetchedAt = httpx.FormatTime(n.FetchedAt)
			out.Notices.Items = noticesOf(n.Items)
		}
	}
	r := httpx.JSON(200, out)
	return httpx.Cached(r.Body, "public, max-age=300", inm), nil
}
