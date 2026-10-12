// Package httpx holds the HTTP plumbing of the Lambda: replies, the error body,
// ETags, gzip and header lookups for API Gateway payload format 2.0.
package httpx

import (
	"bytes"
	"compress/gzip"
	"crypto/sha256"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"strings"

	"github.com/aws/aws-lambda-go/events"
)

// Reply is a response before it is turned into an API Gateway response.
type Reply struct {
	Status int
	Header map[string]string
	Body   []byte
	Err    *Problem
}

// Problem is the content of an error body.
type Problem struct {
	Code   string
	Field  string
	Reason string
}

// JSON replies with v marshalled as the body.
func JSON(status int, v any) Reply {
	body, err := json.Marshal(v)
	if err != nil {
		return Fail(500, "internal", "", "")
	}
	return Reply{Status: status, Body: body}
}

// Fail replies with the standard error body. field and reason may be empty.
func Fail(status int, code, field, reason string) Reply {
	return Reply{Status: status, Err: &Problem{Code: code, Field: field, Reason: reason}}
}

// NoContent is a 204.
func NoContent() Reply { return Reply{Status: 204} }

// With returns the reply with a header set.
func (r Reply) With(key, value string) Reply {
	h := make(map[string]string, len(r.Header)+1)
	for k, v := range r.Header {
		h[k] = v
	}
	h[key] = value
	r.Header = h
	return r
}

// ETag is a strong validator: a quote, the first 16 hex characters of the
// SHA-256 of the body, a quote.
func ETag(body []byte) string {
	sum := sha256.Sum256(body)
	return `"` + hex.EncodeToString(sum[:])[:16] + `"`
}

// Matches reports whether an If-None-Match header lists etag (weak comparison:
// W/ prefixes are ignored; "*" matches anything).
func Matches(ifNoneMatch, etag string) bool {
	for _, v := range strings.Split(ifNoneMatch, ",") {
		v = strings.TrimPrefix(strings.TrimSpace(v), "W/")
		if v == "*" || v == etag {
			return true
		}
	}
	return false
}

// Cached turns a JSON body into a 200 with an ETag and Cache-Control, or into
// a 304 with the same headers when ifNoneMatch lists the ETag.
func Cached(body []byte, cacheControl, ifNoneMatch string) Reply {
	etag := ETag(body)
	r := Reply{Status: 200, Body: body}.
		With("ETag", etag).
		With("Cache-Control", cacheControl).
		With("Vary", "Accept-Encoding")
	if ifNoneMatch != "" && Matches(ifNoneMatch, etag) {
		r.Status = 304
		r.Body = nil
	}
	return r
}

// GzipThreshold is the body size from which responses are compressed.
const GzipThreshold = 1024

// AcceptsGzip reports whether an Accept-Encoding header allows gzip.
func AcceptsGzip(header string) bool {
	for _, part := range strings.Split(header, ",") {
		fields := strings.Split(part, ";")
		coding := strings.ToLower(strings.TrimSpace(fields[0]))
		if coding != "gzip" && coding != "*" {
			continue
		}
		for _, p := range fields[1:] {
			p = strings.ReplaceAll(strings.ToLower(p), " ", "")
			if p == "q=0" || p == "q=0.0" || p == "q=0.00" || p == "q=0.000" {
				return false
			}
		}
		return true
	}
	return false
}

// Finish renders a Reply as an API Gateway response: it adds the content type
// and request id, renders an error body, and gzips large 200 bodies.
func Finish(r Reply, requestID, lang string, gzipOK bool) events.APIGatewayV2HTTPResponse {
	body := r.Body
	if r.Err != nil {
		type detail struct {
			Code      string `json:"code"`
			Message   string `json:"message"`
			Field     string `json:"field,omitempty"`
			Reason    string `json:"reason,omitempty"`
			RequestID string `json:"requestId,omitempty"`
		}
		body, _ = json.Marshal(struct {
			Error detail `json:"error"`
		}{detail{r.Err.Code, message(r.Err.Code, r.Err.Reason, lang), r.Err.Field, r.Err.Reason, requestID}})
	}
	h := map[string]string{}
	for k, v := range r.Header {
		h[k] = v
	}
	if r.Err != nil || r.Status != 204 && r.Status != 304 {
		h["Content-Type"] = "application/json; charset=utf-8"
	}
	if requestID != "" {
		h["X-Request-Id"] = requestID
	}
	if _, ok := h["Cache-Control"]; !ok {
		h["Cache-Control"] = "no-store"
	}
	out := events.APIGatewayV2HTTPResponse{StatusCode: r.Status, Headers: h}
	if r.Status == 204 || r.Status == 304 {
		return out
	}
	if r.Status == 200 && gzipOK && len(body) >= GzipThreshold {
		var buf bytes.Buffer
		zw := gzip.NewWriter(&buf)
		zw.Write(body)
		zw.Close()
		h["Content-Encoding"] = "gzip"
		out.Body = base64.StdEncoding.EncodeToString(buf.Bytes())
		out.IsBase64Encoded = true
		return out
	}
	out.Body = string(body)
	return out
}

// Header reads a request header regardless of case (API Gateway lowercases
// them; tests and other callers may not).
func Header(h map[string]string, name string) string {
	if v, ok := h[strings.ToLower(name)]; ok {
		return v
	}
	for k, v := range h {
		if strings.EqualFold(k, name) {
			return v
		}
	}
	return ""
}
