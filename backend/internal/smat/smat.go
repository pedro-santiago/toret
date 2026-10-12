// Package smat reads SMAT's "Mappa Cantieri" (works orders) and reduces it to
// context notices for the fountains.
//
// This is context, never a water state. SMAT publishes no licence for the
// data, no coordinates and no fountain id: an order is an address string, and a
// fountain is linked to it only when its catalogue street equals the order's
// street after normalisation. The ingest is behind SMAT_ENABLED.
package smat

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"net/http"
	"regexp"
	"sort"
	"strings"
	"time"
	_ "time/tzdata" // Europe/Rome for "today", provided.al2023 may not ship zoneinfo

	"github.com/pedro-santiago/toret/backend/internal/catalogue"
	"github.com/pedro-santiago/toret/backend/internal/fold"
	"github.com/pedro-santiago/toret/backend/internal/store"
)

// Wire constants.
const (
	Source          = "SMAT S.p.A., Mappa Cantieri"
	KindWater       = "waterWorks"
	KindFountain    = "fountainWorks"
	MatchStreet     = "street"
	MinInterval     = time.Hour
	maxNotices      = 300
	fountainObject  = "fontanelle & toretti"
	waterDivision   = "acquedotto"
	connectionObj   = "presa idrica utenza" // a customer's service connection or meter
	maxResponseSize = 8 << 20

	URL = "https://api-octopus.smatorino.it/mappacantieri/index.php/lizmap/service?repository=mappacantieri&project=mappa_cantieri" +
		"&SERVICE=WMS&VERSION=1.3.0&REQUEST=GetFeatureInfo&LAYERS=vm_mappa_cantieri&QUERY_LAYERS=vm_mappa_cantieri&STYLES=" +
		"&CRS=EPSG:4326&BBOX=44.95,7.55,45.2,7.8&WIDTH=800&HEIGHT=800&I=400&J=400&FEATURE_COUNT=5000" +
		"&INFO_FORMAT=application/json&FI_POINT_TOLERANCE=2000"
)

// featureCollection keeps each feature's properties as a map: "numero d'ordine"
// has an apostrophe, which encoding/json does not accept in a struct tag name.
type featureCollection struct {
	Features *[]struct {
		Properties map[string]any `json:"properties"`
	} `json:"features"`
}

// text reads a string property; anything else (null, a number) is "".
func text(p map[string]any, key string) string {
	s, _ := p[key].(string)
	return strings.TrimSpace(s)
}

// The tail of SMAT's address strings: "..., 10131 Torino TO, Italia".
var tail = regexp.MustCompile(`^(.*?),?\s*(\d{5})\s+([^,]+?)\s+[A-Z]{2},\s*Italia\s*$`)

// streetOf extracts the street part of an address when it lies in Turin
// (CAP 101xx and city "Torino", not "San Mauro Torinese" or a street called
// "Via Torino" in another town). "Via Ellero, 22, 10126 Torino TO, Italia"
// gives "Via Ellero"; an intersection "Corso A & Via B, 10131 ..." gives the
// whole "Corso A & Via B".
func streetOf(address string) (string, bool) {
	m := tail.FindStringSubmatch(strings.TrimSpace(address))
	if m == nil || !strings.HasPrefix(m[2], "101") || fold.String(m[3]) != "torino" {
		return "", false
	}
	street, _, _ := strings.Cut(m[1], ",")
	street = strings.TrimSpace(street)
	return street, street != ""
}

func date(s string) (string, bool) {
	if len(s) >= 10 {
		s = s[:10]
	}
	if _, err := time.Parse("2006-01-02", s); err != nil {
		return "", false
	}
	return s, true
}

var rome = func() *time.Location {
	loc, err := time.LoadLocation("Europe/Rome")
	if err != nil {
		return time.FixedZone("CET", 3600)
	}
	return loc
}()

// Parse turns a GetFeatureInfo response into notices:
//   - water division orders (kind waterWorks) and the "FONTANELLE & TORETTI"
//     order (kind fountainWorks), whichever division lists it; nothing else.
//     Customer connection orders (object "PRESA IDRICA UTENZA": new meters,
//     rebuilt service connections) are dropped: they are one building's pipe,
//     not the street's supply;
//   - only orders whose address is in Turin;
//   - only orders that have started (startedOn is not after today in Rome),
//     because the app words them "started <date>";
//   - an order that matches no fountain is kept with an empty fountainIDs.
//
// A response without a "features" array is an error, so a changed or broken
// upstream never replaces a good cache with an empty one.
func Parse(body []byte, cat *catalogue.Catalogue, fetchedAt time.Time) ([]store.Notice, error) {
	var fc featureCollection
	if err := json.Unmarshal(body, &fc); err != nil {
		return nil, fmt.Errorf("smat: %w", err)
	}
	if fc.Features == nil {
		return nil, errors.New("smat: response has no features array")
	}
	today := fetchedAt.In(rome).Format("2006-01-02")
	fetchedAt = fetchedAt.UTC().Truncate(time.Second)

	seen := map[string]bool{}
	notices := []store.Notice{}
	for _, f := range *fc.Features {
		p := f.Properties
		kind := KindWater
		switch {
		case strings.EqualFold(text(p, "oggetto_di_intervento"), fountainObject):
			kind = KindFountain
		case strings.EqualFold(text(p, "divisione"), waterDivision):
			if strings.EqualFold(text(p, "oggetto_di_intervento"), connectionObj) {
				continue
			}
		default:
			continue
		}
		street, ok := streetOf(text(p, "indirizzo"))
		if !ok {
			continue
		}
		started, ok := date(text(p, "data_inizio"))
		if !ok || started > today {
			continue
		}
		end, _ := date(text(p, "data_fine_prevista"))
		order := text(p, "numero d'ordine")
		sum := sha256.Sum256([]byte("smat:" + order))
		id := hex.EncodeToString(sum[:])[:12]
		if order == "" || seen[id] {
			continue
		}
		seen[id] = true
		notices = append(notices, store.Notice{
			ID: id, Kind: kind, Street: street, FountainIDs: match(cat, street), Match: MatchStreet,
			StartedOn: started, PlannedEnd: end, Source: Source, FetchedAt: fetchedAt,
		})
	}
	sort.Slice(notices, func(i, j int) bool {
		if notices[i].StartedOn != notices[j].StartedOn {
			return notices[i].StartedOn > notices[j].StartedOn
		}
		return notices[i].ID < notices[j].ID
	})
	if len(notices) > maxNotices {
		notices = notices[:maxNotices]
	}
	return notices, nil
}

// match returns the sorted ids of the fountains on the street, or on any of
// the streets of an intersection ("Corso A & Via B").
func match(cat *catalogue.Catalogue, street string) []string {
	ids := []string{}
	seen := map[string]bool{}
	for _, part := range strings.Split(street, "&") {
		for _, id := range cat.OnStreet(part) {
			if !seen[id] {
				seen[id] = true
				ids = append(ids, id)
			}
		}
	}
	sort.Strings(ids)
	return ids
}

// Client fetches the works orders.
type Client struct {
	HTTP *http.Client
	URL  string // defaults to URL
}

// Fetch calls the Mappa Cantieri service once and returns its raw JSON.
func (c Client) Fetch(ctx context.Context) ([]byte, error) {
	url := c.URL
	if url == "" {
		url = URL
	}
	hc := c.HTTP
	if hc == nil {
		hc = &http.Client{Timeout: 30 * time.Second}
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodGet, url, nil)
	if err != nil {
		return nil, err
	}
	req.Header.Set("User-Agent", "toret-ingest (+https://github.com/pedro-santiago/toret)")
	res, err := hc.Do(req)
	if err != nil {
		return nil, err
	}
	defer res.Body.Close()
	if res.StatusCode != http.StatusOK {
		return nil, fmt.Errorf("smat: upstream status %d", res.StatusCode)
	}
	return io.ReadAll(io.LimitReader(res.Body, maxResponseSize))
}
