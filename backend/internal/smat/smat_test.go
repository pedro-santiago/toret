package smat

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"os"
	"reflect"
	"strings"
	"testing"
	"time"

	"github.com/pedro-santiago/toret/backend/internal/catalogue"
	"github.com/pedro-santiago/toret/backend/internal/store"
)

var fetched = time.Date(2026, 10, 12, 16, 5, 7, 0, time.UTC)

func cat(t *testing.T) *catalogue.Catalogue {
	t.Helper()
	c, err := catalogue.Embedded()
	if err != nil {
		t.Fatal(err)
	}
	return c
}

func byStreet(ns []store.Notice) map[string]store.Notice {
	m := map[string]store.Notice{}
	for _, n := range ns {
		m[n.Street] = n
	}
	return m
}

// testdata/mappa_cantieri.json is 21 features of one real response (fetched
// 2026-10-12): Turin and other towns, ACQUEDOTTO and FOGNATURA, intersections,
// abbreviations ("C.so", "V.", "Str.", "SC") and the FONTANELLE & TORETTI order.
func TestParseFixture(t *testing.T) {
	raw, err := os.ReadFile("testdata/mappa_cantieri.json")
	if err != nil {
		t.Fatal(err)
	}
	var in struct{ Features []json.RawMessage }
	json.Unmarshal(raw, &in)
	if len(in.Features) != 21 {
		t.Fatalf("fixture has %d features", len(in.Features))
	}

	got, err := Parse(raw, cat(t), fetched)
	if err != nil {
		t.Fatal(err)
	}
	m := byStreet(got)

	// Excluded: the sewer order, the five other-town orders (Chivasso x3, San
	// Mauro Torinese, "Via Torino" in Salassa).
	for _, street := range []string{"Largo Millefonti", "Corso G. Ferraris", "Via Rivera", "Piazza Nassirya", "Via Torino"} {
		if _, ok := m[street]; ok {
			t.Errorf("%q must be excluded", street)
		}
	}
	if len(got) != 15 { // 21 features - 1 sewer - 5 other towns
		t.Errorf("%d notices, want 15", len(got))
	}

	for _, tc := range []struct {
		street string
		kind   string
		ids    []string
		start  string
		end    string
	}{
		{"Corso Stati Uniti", KindWater, []string{"3287889713", "422952469"}, "2026-09-24", "2026-11-28"},
		{"C.so Francesco Ferrucci", KindWater, []string{"1371984107", "5335920473", "5562792829", "9577650963"}, "2026-05-25", ""},
		{"Piazza Carlo Alberto Dalla Chiesa", KindFountain, []string{"4289455495"}, "2026-09-07", ""},
		{"SC di Superga", KindWater, []string{"10839646105", "7243439610"}, "2026-09-14", "2026-12-31"},
		{"Corso Massimo d'Azeglio", KindWater, []string{"1456706457", "4069862135", "429780458"}, "2026-10-12", ""},
		{"V. Luigi Lavazza", KindWater, []string{}, "2026-09-24", ""},
		{"Str. dei Biasoni", KindWater, []string{}, "2026-10-07", ""},
	} {
		n, ok := m[tc.street]
		if !ok {
			t.Errorf("%q missing", tc.street)
			continue
		}
		if n.Kind != tc.kind || !reflect.DeepEqual(n.FountainIDs, tc.ids) || n.StartedOn != tc.start || n.PlannedEnd != tc.end {
			t.Errorf("%q = %+v", tc.street, n)
		}
		if n.Match != "street" || n.Source != "SMAT S.p.A., Mappa Cantieri" || !n.FetchedAt.Equal(fetched) || len(n.ID) != 12 {
			t.Errorf("%q constants = %+v", tc.street, n)
		}
	}

	// An intersection is matched on both streets.
	n := m["Corso Unione Sovietica & Via Cesare Pavese"]
	if len(n.FountainIDs) != 4 {
		t.Errorf("intersection matched %v, want the 2 + 2 fountains of both streets", n.FountainIDs)
	}
	if n := m["Corso Cairoli & Lungo Po Armando Diaz"]; !reflect.DeepEqual(n.FountainIDs, []string{"426873389"}) {
		t.Errorf("Cairoli & Diaz = %v", n.FountainIDs)
	}
	// Order: newest start first.
	for i := 1; i < len(got); i++ {
		if got[i-1].StartedOn < got[i].StartedOn {
			t.Errorf("not sorted by start date at %d: %s then %s", i, got[i-1].StartedOn, got[i].StartedOn)
		}
	}
	// Two orders on Via Ellero are two notices.
	count := 0
	for _, n := range got {
		if n.Street == "Via Ellero" {
			count++
		}
	}
	if count != 2 {
		t.Errorf("Via Ellero notices = %d, want 2", count)
	}
	// Stable ids: parsing twice gives the same ones.
	again, _ := Parse(raw, cat(t), fetched.Add(time.Hour))
	for i := range got {
		if got[i].ID != again[i].ID {
			t.Errorf("id %d changed between fetches", i)
		}
	}
	// No status-like member ever leaves the package.
	out, _ := json.Marshal(got)
	for _, banned := range []string{"status", "dry", "off", "available", "running"} {
		if strings.Contains(strings.ToLower(string(out)), `"`+banned+`"`) {
			t.Errorf("a notice has a %q member", banned)
		}
	}
}

func feature(division, object, address, start, end string) string {
	e := "null"
	if end != "" {
		e = `"` + end + `"`
	}
	return `{"properties":{"divisione":"` + division + `","oggetto_di_intervento":"` + object + `","indirizzo":"` + address +
		`","data_inizio":"` + start + `","data_fine_prevista":` + e + `,"numero d'ordine":"` + address + start + `"}}`
}

func TestParseRules(t *testing.T) {
	c := cat(t)
	const turin = ", 10128 Torino TO, Italia"
	for _, tc := range []struct {
		name string
		feat string
		want int
	}{
		{"water division", feature("ACQUEDOTTO", "CONDOTTA RETE IDRICA", "Corso Stati Uniti, 38"+turin, "2026-09-24", ""), 1},
		{"water lower case", feature("acquedotto", "x", "Corso Stati Uniti, 38"+turin, "2026-09-24", ""), 1},
		{"sewer", feature("FOGNATURA", "(FG) COLLETTORE MISTO", "Corso Stati Uniti, 38"+turin, "2026-09-24", ""), 0},
		{"fountain order in another division", feature("FOGNATURA", "FONTANELLE & TORETTI", "Corso Stati Uniti, 38"+turin, "2026-09-24", ""), 1},
		{"no division", feature("", "x", "Corso Stati Uniti, 38"+turin, "2026-09-24", ""), 0},
		{"other town", feature("ACQUEDOTTO", "x", "Corso Stati Uniti, 38, 10034 Chivasso TO, Italia", "2026-09-24", ""), 0},
		{"street named Torino elsewhere", feature("ACQUEDOTTO", "x", "Via Torino, 10080 Salassa TO, Italia", "2026-09-24", ""), 0},
		{"Torinese is not Torino", feature("ACQUEDOTTO", "x", "Via Roma, 10099 San Mauro Torinese TO, Italia", "2026-09-24", ""), 0},
		{"CAP outside Turin", feature("ACQUEDOTTO", "x", "Via Roma, 10040 Torino TO, Italia", "2026-09-24", ""), 0},
		{"unparseable address", feature("ACQUEDOTTO", "x", "somewhere", "2026-09-24", ""), 0},
		{"no street", feature("ACQUEDOTTO", "x", "10128 Torino TO, Italia", "2026-09-24", ""), 0},
		{"starts today", feature("ACQUEDOTTO", "x", "Via Po, 1"+turin, "2026-10-12", ""), 1},
		{"starts tomorrow", feature("ACQUEDOTTO", "x", "Via Po, 1"+turin, "2026-10-13", ""), 0},
		{"no start date", feature("ACQUEDOTTO", "x", "Via Po, 1"+turin, "", ""), 0},
		{"start with time", feature("ACQUEDOTTO", "x", "Via Po, 1"+turin, "2026-09-24T00:00:00", ""), 1},
		{"bad end date dropped", feature("ACQUEDOTTO", "x", "Via Po, 1"+turin, "2026-09-24", "soon"), 1},
	} {
		got, err := Parse([]byte(`{"features":[`+tc.feat+`]}`), c, fetched)
		if err != nil || len(got) != tc.want {
			t.Errorf("%s: %d notices, err %v; want %d", tc.name, len(got), err, tc.want)
		}
	}

	// "Today" is the date in Rome, not in UTC: at 22:30Z on the 12th it is the 13th there.
	late := time.Date(2026, 10, 12, 22, 30, 0, 0, time.UTC)
	got, _ := Parse([]byte(`{"features":[`+feature("ACQUEDOTTO", "x", "Via Po, 1"+turin, "2026-10-13", "")+`]}`), c, late)
	if len(got) != 1 {
		t.Error("an order starting on the 13th has started at 00:30 Rome time")
	}

	// A bad end date is dropped; a missing end is omitted.
	got, _ = Parse([]byte(`{"features":[`+feature("ACQUEDOTTO", "x", "Via Po, 1"+turin, "2026-09-24", "soon")+`]}`), c, fetched)
	if got[0].PlannedEnd != "" {
		t.Errorf("planned end = %q", got[0].PlannedEnd)
	}

	// The same order twice is one notice.
	f := feature("ACQUEDOTTO", "x", "Via Po, 1"+turin, "2026-09-24", "")
	got, _ = Parse([]byte(`{"features":[`+f+`,`+f+`]}`), c, fetched)
	if len(got) != 1 {
		t.Errorf("duplicates: %d notices", len(got))
	}
	// An order with no number cannot be identified and is skipped.
	got, _ = Parse([]byte(`{"features":[{"properties":{"divisione":"ACQUEDOTTO","indirizzo":"Via Po, 1`+turin+`","data_inizio":"2026-09-24"}}]}`), c, fetched)
	if len(got) != 0 {
		t.Errorf("order without a number: %d notices", len(got))
	}
}

func TestParseRejectsBrokenUpstream(t *testing.T) {
	c := cat(t)
	for name, body := range map[string]string{
		"html":          `<html>maintenance</html>`,
		"no features":   `{"error":"boom"}`,
		"null features": `{"features":null}`,
	} {
		if _, err := Parse([]byte(body), c, fetched); err == nil {
			t.Errorf("%s: accepted", name)
		}
	}
	// An empty list is a valid answer: no works.
	got, err := Parse([]byte(`{"features":[]}`), c, fetched)
	if err != nil || got == nil || len(got) != 0 {
		t.Errorf("empty: %v, %v", got, err)
	}
}

func TestStreetOf(t *testing.T) {
	for _, tc := range []struct {
		in   string
		want string
		ok   bool
	}{
		{"Via Ellero, 22, 10126 Torino TO, Italia", "Via Ellero", true},
		{"Piazza Adriano, 17/I, 10138 Torino TO, Italia", "Piazza Adriano", true},
		{"Corso Moncalieri & Corso Fiume, 10131 Torino TO, Italia", "Corso Moncalieri & Corso Fiume", true},
		{"Str. Antica di Collegno, 190/15, 10146 Torino TO, Italia", "Str. Antica di Collegno", true},
		{"Lungo Po Armando Diaz, 10123 Torino TO, Italia", "Lungo Po Armando Diaz", true},
		{"Via Ellero, 22, 10126 TORINO TO, Italia", "Via Ellero", true},
		{"Via Roma, 10090 Rosta TO, Italia", "", false},
		{"", "", false},
	} {
		got, ok := streetOf(tc.in)
		if got != tc.want || ok != tc.ok {
			t.Errorf("streetOf(%q) = %q, %v", tc.in, got, ok)
		}
	}
}

func TestCap(t *testing.T) {
	var feats []string
	for i := 0; i < 400; i++ {
		f := feature("ACQUEDOTTO", "x", "Via Po, 1, 10128 Torino TO, Italia", "2026-09-24", "")
		feats = append(feats, strings.Replace(f, `"numero d'ordine":"`, `"numero d'ordine":"n`+string(rune('a'+i%26))+strings.Repeat("x", i/26)+`-`, 1))
	}
	got, err := Parse([]byte(`{"features":[`+strings.Join(feats, ",")+`]}`), cat(t), fetched)
	if err != nil || len(got) != 300 {
		t.Errorf("got %d notices, err %v; want the cap of 300", len(got), err)
	}
}

func TestFetch(t *testing.T) {
	body, _ := os.ReadFile("testdata/mappa_cantieri.json")
	var query string
	srv := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		query = r.URL.RawQuery
		if r.URL.Path == "/down" {
			http.Error(w, "no", http.StatusBadGateway)
			return
		}
		w.Write(body)
	}))
	defer srv.Close()
	got, err := Client{URL: srv.URL + "/ok?a=1"}.Fetch(context.Background())
	if err != nil || len(got) != len(body) || query != "a=1" {
		t.Fatalf("Fetch: %d bytes, err %v, query %q", len(got), err, query)
	}
	if _, err := (Client{URL: srv.URL + "/down"}).Fetch(context.Background()); err == nil {
		t.Error("a 502 must be an error")
	}
	if !strings.Contains(URL, "FEATURE_COUNT=5000") || !strings.Contains(URL, "INFO_FORMAT=application/json") {
		t.Error("the upstream URL lost a parameter")
	}
}
