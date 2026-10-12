package catalogue

import (
	"bytes"
	"os"
	"reflect"
	"testing"
)

func TestEmbeddedHas723(t *testing.T) {
	c, err := Embedded()
	if err != nil {
		t.Fatal(err)
	}
	if c.Len() != 723 {
		t.Fatalf("catalogue has %d fountains, want 723", c.Len())
	}
	if f, ok := c.Get("421310659"); !ok || f.Street != "Corso Vittorio Emanuele II" {
		t.Errorf("Get(421310659) = %+v, %v", f, ok)
	}
	if _, ok := c.Get("1"); ok {
		t.Error("unknown id found")
	}
}

// The embedded copy must not drift from the app's catalogue.
func TestCopyMatchesApp(t *testing.T) {
	app, err := os.ReadFile("../../../Shared/Resources/fountains.json")
	if err != nil {
		t.Skip("app catalogue not next to the backend: ", err)
	}
	copy, err := os.ReadFile("../../data/fountains.json")
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(app, copy) {
		t.Error("backend/data/fountains.json differs from Shared/Resources/fountains.json: run `make data`")
	}
}

func TestNormaliseStreet(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"Corso Vittorio Emanuele II", "corso vittorio emanuele ii"},
		{"C.so Francia", "corso francia"},
		{"C.so Francesco Ferrucci", "corso francesco ferrucci"},
		{"V. Ormea", "via ormea"},
		{"Str. dei Biasoni", "strada dei biasoni"},
		{"S.da di Settimo", "strada di settimo"},
		{"SC di Superga", "strada comunale di superga"},
		{"Corso Massimo d'Azeglio", "corso massimo d azeglio"},
		{"Corso Massimo D’Azeglio", "corso massimo d azeglio"},
		{"Corso Unità d'Italia", "corso unita d italia"},
		{"  Via   Po  ", "via po"},
		{"Piazza Castello", "piazza castello"},
		{"", ""},
		{"...", ""},
	} {
		if got := NormaliseStreet(tc.in); got != tc.want {
			t.Errorf("NormaliseStreet(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestOnStreet(t *testing.T) {
	c, err := Load([]byte(`[
		{"id":"2","kind":"fountain","street":"Corso Francia"},
		{"id":"1","kind":"toret","street":"Corso Francia"},
		{"id":"3","kind":"toret"},
		{"id":"4","kind":"toret","street":"Via Po"}]`))
	if err != nil {
		t.Fatal(err)
	}
	if got := c.OnStreet("C.so Francia"); !reflect.DeepEqual(got, []string{"1", "2"}) {
		t.Errorf("OnStreet(C.so Francia) = %v", got)
	}
	if got := c.OnStreet(""); got != nil {
		t.Errorf("an empty street must match nothing, got %v", got)
	}
	if got := c.OnStreet("Via Roma"); got != nil {
		t.Errorf("OnStreet(Via Roma) = %v", got)
	}
}

func TestLoadRejectsGarbage(t *testing.T) {
	for _, in := range []string{`{}`, `[{"kind":"x"}]`, `nope`} {
		if _, err := Load([]byte(in)); err == nil {
			t.Errorf("Load(%s) accepted", in)
		}
	}
}
