// Package catalogue is the fountain catalogue embedded at build time: the ids
// a report may refer to, and which fountains stand on which street.
package catalogue

import (
	"encoding/json"
	"fmt"
	"sort"
	"strings"
	"unicode"

	"github.com/pedro-santiago/toret/backend/data"
	"github.com/pedro-santiago/toret/backend/internal/fold"
)

// Fountain is the part of a catalogue entry the API needs.
type Fountain struct {
	ID     string `json:"id"`
	Kind   string `json:"kind"`
	Street string `json:"street"`
	Zone   string `json:"zone"`
}

// Catalogue indexes the fountains by id and by normalised street.
type Catalogue struct {
	byID     map[string]Fountain
	byStreet map[string][]string
}

// Load parses a fountains.json document.
func Load(raw []byte) (*Catalogue, error) {
	var list []Fountain
	if err := json.Unmarshal(raw, &list); err != nil {
		return nil, fmt.Errorf("catalogue: %w", err)
	}
	c := &Catalogue{byID: make(map[string]Fountain, len(list)), byStreet: map[string][]string{}}
	for _, f := range list {
		if f.ID == "" {
			return nil, fmt.Errorf("catalogue: entry without id")
		}
		c.byID[f.ID] = f
		if key := NormaliseStreet(f.Street); key != "" {
			c.byStreet[key] = append(c.byStreet[key], f.ID)
		}
	}
	for _, ids := range c.byStreet {
		sort.Strings(ids)
	}
	return c, nil
}

// Embedded loads the catalogue compiled into the binary.
func Embedded() (*Catalogue, error) { return Load(data.Fountains) }

// Len is the number of fountains.
func (c *Catalogue) Len() int { return len(c.byID) }

// Get looks a fountain up by its OSM node id.
func (c *Catalogue) Get(id string) (Fountain, bool) {
	f, ok := c.byID[id]
	return f, ok
}

// OnStreet returns the ids of the fountains whose street equals the given one
// after normalisation, sorted. The slice must not be modified.
func (c *Catalogue) OnStreet(street string) []string {
	return c.byStreet[NormaliseStreet(street)]
}

// abbreviations are the spellings of a street type that SMAT's address strings
// use ("C.so Francia", "V. Ormea", "Str. dei Biasoni", "SC di Superga"), keyed
// by the first word with its dots removed.
var abbreviations = map[string]string{
	"cso": "corso", "v": "via", "vl": "viale", "vle": "viale", "str": "strada",
	"sda": "strada", "sc": "strada comunale", "pza": "piazza", "pzza": "piazza",
	"lgo": "largo",
}

// NormaliseStreet makes two spellings of one street comparable: case and
// accents folded, dots dropped, apostrophes and other punctuation turned into
// spaces, spaces collapsed, and a leading abbreviation spelled out ("C.so" is
// "corso"). Streets with no letters normalise to "".
func NormaliseStreet(s string) string {
	s = strings.ReplaceAll(fold.String(s), ".", "")
	words := strings.FieldsFunc(s, func(r rune) bool { return !unicode.IsLetter(r) && !unicode.IsDigit(r) })
	if len(words) == 0 {
		return ""
	}
	if full, ok := abbreviations[words[0]]; ok {
		words[0] = full
	}
	return strings.Join(words, " ")
}
