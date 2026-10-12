package reports

import "testing"

// The table is the one in docs/backend/api.md section 6.4, plus the boundaries
// of the contact pattern.
func TestCheck(t *testing.T) {
	for _, tc := range []struct {
		note string
		want Verdict
	}{
		{"Água gelada, sem fila.", OK},
		{"Ligue 011 123 4567", ContainsContact},
		{"veja www.exemplo.com", ContainsContact},
		{"fala com @fulano", ContainsContact},
		{"Fuck this", Objectionable},
		{"p#ta", OK},
		{"f0da", OK},
		{"put4", Objectionable},
		{"Scunthorpe", OK},
		{"FUCK", Objectionable},
		{"Cuzão!", Objectionable},
		{"que $tronzo", Objectionable}, // $ becomes s
		{"str0nzo", Objectionable},
		{"https://example.org/x", ContainsContact},
		{"mande mail para a@b.com", ContainsContact},
		{"abre às 10", OK},
		{"2 de 5 estrelas, 12 minutos", OK},
		{"12345678", OK}, // eight digits: below the phone pattern (nine or more match)
		{"123456789", ContainsContact},
		{"+39 011 123 4567", ContainsContact},
		{"", OK},
	} {
		if got := Check(tc.note); got != tc.want {
			t.Errorf("Check(%q) = %v, want %v", tc.note, got, tc.want)
		}
	}
}
