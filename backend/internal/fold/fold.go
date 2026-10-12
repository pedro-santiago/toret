// Package fold lowercases text and strips diacritics, standard library only.
//
// Foundation's `folding(options: [.diacriticInsensitive, .caseInsensitive])`
// (used by NoteFilter in the app) is not in Go's standard library and
// golang.org/x/text is not a dependency, so the Latin-1 Supplement and Latin
// Extended-A letters are mapped by hand. Letters outside those blocks are only
// lowercased.
package fold

import (
	"strings"
	"unicode"
)

var table = func() map[rune]string {
	m := make(map[rune]string)
	add := func(to string, from string) {
		for _, r := range from {
			m[r] = to
		}
	}
	add("a", "àáâãäåāăą")
	add("c", "çćĉċč")
	add("d", "ďđð")
	add("e", "èéêëēĕėęě")
	add("g", "ĝğġģ")
	add("h", "ĥħ")
	add("i", "ìíîïĩīĭįı")
	add("j", "ĵ")
	add("k", "ķ")
	add("l", "ĺļľŀł")
	add("n", "ñńņňŉ")
	add("o", "òóôõöøōŏő")
	add("r", "ŕŗř")
	add("s", "śŝşš")
	add("t", "ţťŧ")
	add("u", "ùúûüũūŭůűų")
	add("w", "ŵ")
	add("y", "ýÿŷ")
	add("z", "źżž")
	add("ss", "ß")
	add("ae", "æ")
	add("oe", "œ")
	return m
}()

// String returns s lowercased, with accents removed and combining marks dropped.
func String(s string) string {
	var b strings.Builder
	b.Grow(len(s))
	for _, r := range s {
		if unicode.Is(unicode.Mn, r) {
			continue
		}
		r = unicode.ToLower(r)
		if to, ok := table[r]; ok {
			b.WriteString(to)
			continue
		}
		b.WriteRune(r)
	}
	return b.String()
}
