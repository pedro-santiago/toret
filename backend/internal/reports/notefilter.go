package reports

import (
	"regexp"
	"strings"
	"unicode"

	"github.com/pedro-santiago/toret/backend/internal/fold"
)

// Verdict is the outcome of the content filter.
type Verdict int

const (
	OK Verdict = iota
	// Objectionable: slurs and explicit language.
	Objectionable
	// ContainsContact: a link, an address or a phone number.
	ContainsContact
)

// This file is a port of Toret/Community/NoteFilter.swift, which stays the
// single source of truth: when the Swift file changes, this one and the vectors
// in notefilter_test.go change in the same commit.

// contact is the Swift pattern with ICU's Unicode-aware \d spelled \p{Nd}.
var contact = regexp.MustCompile(`(?i)(https?://|www\.|[a-z0-9-]+\.(com|net|org|it|br|io|me)\b|@[a-z0-9_.]{3,}|\+?\p{Nd}[\p{Nd}\s().-]{7,}\p{Nd})`)

// substitutions are the ones people use to dodge a filter, and only these are
// undone ("p#ta" stays as it is).
var substitutions = map[rune]rune{'0': 'o', '1': 'i', '3': 'e', '4': 'a', '5': 's', '@': 'a', '$': 's'}

// blocked is Portuguese, Italian and English, matched as whole words.
var blocked = map[string]bool{
	"puta": true, "putas": true, "viado": true, "viada": true, "caralho": true, "buceta": true,
	"cuzao": true, "arrombado": true, "fdp": true,
	"cazzo": true, "puttana": true, "troia": true, "stronzo": true, "frocio": true, "negro": true,
	"fuck": true, "fucking": true, "bitch": true, "cunt": true, "nigger": true, "faggot": true, "whore": true,
}

// Check applies the content filter to a note.
func Check(note string) Verdict {
	if contact.MatchString(note) {
		return ContainsContact
	}
	folded := []rune(fold.String(note))
	for i, r := range folded {
		if to, ok := substitutions[r]; ok {
			folded[i] = to
		}
	}
	for _, word := range strings.FieldsFunc(string(folded), func(r rune) bool { return !unicode.IsLetter(r) }) {
		if blocked[word] {
			return Objectionable
		}
	}
	return OK
}
