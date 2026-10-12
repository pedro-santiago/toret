package api

import (
	"bytes"
	"compress/gzip"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"log/slog"
	"strings"
	"testing"
	"time"

	"github.com/aws/aws-lambda-go/events"

	"github.com/pedro-santiago/toret/backend/internal/catalogue"
	"github.com/pedro-santiago/toret/backend/internal/handle"
	"github.com/pedro-santiago/toret/backend/internal/ratelimit"
	"github.com/pedro-santiago/toret/backend/internal/store"
)

var (
	epoch  = time.Date(2026, 10, 12, 12, 0, 0, 0, time.UTC)
	pepper = []byte("toret-test-pepper")
)

const fountain = "421310659" // Corso Vittorio Emanuele II

// env is a Handler over an in-memory store with a clock the test moves.
type env struct {
	t    *testing.T
	h    *Handler
	mem  *store.Memory
	now  time.Time
	logs *bytes.Buffer
	n    int // counter for fresh ids and tokens
}

type option func(*Config)

func newEnv(t *testing.T, opts ...option) *env {
	t.Helper()
	cat, err := catalogue.Embedded()
	if err != nil {
		t.Fatal(err)
	}
	e := &env{t: t, mem: store.NewMemory(), now: epoch, logs: &bytes.Buffer{}}
	cfg := Config{
		Store: e.mem, Catalogue: cat,
		Pepper: func(context.Context) ([]byte, error) { return pepper, nil },
		// Generous by default; the rate-limit tests set their own.
		Limits: ratelimit.Config{InstallPerHour: 1000, IPPerHour: 10000},
		Now:    func() time.Time { return e.now },
		Logger: slog.New(slog.NewJSONHandler(e.logs, nil)),
	}
	for _, o := range opts {
		o(&cfg)
	}
	e.h = New(cfg)
	return e
}

// call describes one request.
type call struct {
	method, path string
	headers      map[string]string
	query        map[string]string
	body         string
	b64          bool
	ip           string
}

func (e *env) do(c call) events.APIGatewayV2HTTPResponse {
	e.t.Helper()
	req := events.APIGatewayV2HTTPRequest{
		RouteKey:              routeKey(c.method, c.path),
		Headers:               map[string]string{},
		QueryStringParameters: c.query,
		Body:                  c.body,
		IsBase64Encoded:       c.b64,
		PathParameters:        pathParams(c.path),
	}
	for k, v := range c.headers {
		req.Headers[strings.ToLower(k)] = v // API Gateway lowercases header names
	}
	req.RequestContext.RequestID = "req-" + fmt.Sprint(e.n)
	req.RequestContext.HTTP.SourceIP = c.ip
	if c.ip == "" {
		req.RequestContext.HTTP.SourceIP = "203.0.113.7"
	}
	resp, err := e.h.Handle(context.Background(), req)
	if err != nil {
		e.t.Fatalf("Handle returned an error: %v", err)
	}
	return resp
}

func routeKey(method, path string) string {
	parts := strings.Split(strings.Trim(path, "/"), "/")
	switch {
	case len(parts) == 4 && parts[1] == "fountains" && parts[3] == "reports":
		return method + " /v1/fountains/{id}/reports"
	case len(parts) == 4 && parts[1] == "reports" && parts[3] == "flag":
		return method + " /v1/reports/{id}/flag"
	case len(parts) == 3 && parts[1] == "reports":
		return method + " /v1/reports/{id}"
	}
	return method + " " + path
}

func pathParams(path string) map[string]string {
	parts := strings.Split(strings.Trim(path, "/"), "/")
	switch {
	case len(parts) == 4 && (parts[1] == "fountains" || parts[1] == "reports"):
		return map[string]string{"id": parts[2]}
	case len(parts) == 3 && parts[1] == "reports":
		return map[string]string{"id": parts[2]}
	}
	return nil
}

func uuid(n int) string { return fmt.Sprintf("00000000-0000-4000-8000-%012d", n) }

func token(n int) string { return fmt.Sprintf("install-token-%04d-abcd", n) }

func (e *env) fresh() int { e.n++; return e.n }

func jsonHeaders(tok string) map[string]string {
	return map[string]string{"Content-Type": "application/json; charset=utf-8", "X-Toret-Install": tok, "X-Toret-Client": "1.0.0+42"}
}

// payload is a valid report body; over replaces members (nil deletes one).
func payload(id string, over map[string]any) string {
	m := map[string]any{
		"id": id, "fountainID": fountain, "state": "running", "rating": 5,
		"tags": []string{"cold", "clean"}, "note": "Água gelada, sem fila.",
		"date": epoch.Add(-19 * time.Minute).Format(time.RFC3339),
	}
	for k, v := range over {
		if v == nil {
			delete(m, k)
		} else {
			m[k] = v
		}
	}
	b, _ := json.Marshal(m)
	return string(b)
}

func (e *env) post(tok string, body string) events.APIGatewayV2HTTPResponse {
	return e.do(call{method: "POST", path: "/v1/reports", headers: jsonHeaders(tok), body: body})
}

// submit posts a new valid report from a fresh install; over tweaks the body.
func (e *env) submit(over map[string]any) (id string, tok string, resp events.APIGatewayV2HTTPResponse) {
	e.t.Helper()
	n := e.fresh()
	id, tok = uuid(n), token(n)
	resp = e.post(tok, payload(id, over))
	if resp.StatusCode != 201 {
		e.t.Fatalf("submit: %d %s", resp.StatusCode, resp.Body)
	}
	return id, tok, resp
}

func (e *env) get(path string, query map[string]string, headers map[string]string) events.APIGatewayV2HTTPResponse {
	return e.do(call{method: "GET", path: path, query: query, headers: headers})
}

func (e *env) flag(tok, id, ip, body string) events.APIGatewayV2HTTPResponse {
	return e.do(call{method: "POST", path: "/v1/reports/" + id + "/flag", headers: jsonHeaders(tok), body: body, ip: ip})
}

func (e *env) delete(tok, id string) events.APIGatewayV2HTTPResponse {
	return e.do(call{method: "DELETE", path: "/v1/reports/" + id, headers: map[string]string{"X-Toret-Install": tok}})
}

// body returns the response body decoded from base64/gzip as needed.
func plain(t *testing.T, r events.APIGatewayV2HTTPResponse) []byte {
	t.Helper()
	raw := []byte(r.Body)
	if r.IsBase64Encoded {
		dec, err := base64.StdEncoding.DecodeString(r.Body)
		if err != nil {
			t.Fatal(err)
		}
		raw = dec
	}
	if r.Headers["Content-Encoding"] == "gzip" {
		zr, err := gzip.NewReader(bytes.NewReader(raw))
		if err != nil {
			t.Fatal(err)
		}
		raw, err = io.ReadAll(zr)
		if err != nil {
			t.Fatal(err)
		}
	}
	return raw
}

// decode parses a JSON body into a generic value.
func decode(t *testing.T, r events.APIGatewayV2HTTPResponse) map[string]any {
	t.Helper()
	var m map[string]any
	if err := json.Unmarshal(plain(t, r), &m); err != nil {
		t.Fatalf("body is not a JSON object: %v: %s", err, r.Body)
	}
	return m
}

type problem struct {
	code, field, reason, requestID, message string
}

func errOf(t *testing.T, r events.APIGatewayV2HTTPResponse) problem {
	t.Helper()
	e, _ := decode(t, r)["error"].(map[string]any)
	if e == nil {
		t.Fatalf("no error object in %s", r.Body)
	}
	s := func(k string) string { v, _ := e[k].(string); return v }
	return problem{s("code"), s("field"), s("reason"), s("requestId"), s("message")}
}

func ids(t *testing.T, r events.APIGatewayV2HTTPResponse) []string {
	t.Helper()
	list, _ := decode(t, r)["reports"].([]any)
	out := make([]string, len(list))
	for i, v := range list {
		out[i] = v.(map[string]any)["id"].(string)
	}
	return out
}

func authorOf(token string) string { return handle.Author(token) }

func hashOf(token string) string { return handle.InstallHash(pepper, token) }

var errBoom = errors.New("boom")
