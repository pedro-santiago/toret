package fold

import "testing"

func TestString(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"Água GELADA", "agua gelada"},
		{"Cuzão", "cuzao"},
		{"Corso Unità d'Italia", "corso unita d'italia"},
		{"Niccolò", "niccolo"},
		{"é", "e"}, // decomposed é
		{"Straße", "strasse"},
		{"plain", "plain"},
	} {
		if got := String(tc.in); got != tc.want {
			t.Errorf("String(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}
