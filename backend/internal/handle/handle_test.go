package handle

import "testing"

var pepper = []byte("toret-test-pepper")

// Vectors from docs/backend/api.md section 7, cross-checked with CryptoKit.
func TestVectors(t *testing.T) {
	for _, tc := range []struct{ token, author, install string }{
		{"5B0C6E0D-7F7B-4D5E-9E3A-2C1F8A4B9D10", "Visitante E95596", "875c150fd8da0ca82b126a92d07c18a2bc896a13546db56f1175764871d48911"},
		{"00000000-0000-4000-8000-000000000000", "Visitante 75CD2D", "69307b71f9238ae26e8ecbc6f0f14c46f79e87ee38cc7b481d19978c54b51225"},
	} {
		if got := Author(tc.token); got != tc.author {
			t.Errorf("Author(%q) = %q, want %q", tc.token, got, tc.author)
		}
		if got := InstallHash(pepper, tc.token); got != tc.install {
			t.Errorf("InstallHash(%q) = %q, want %q", tc.token, got, tc.install)
		}
	}
	if got, want := IPHash(pepper, "203.0.113.7"), "37cea502c2d2c94e6df6ab280294eced6331705eb23d99671e29af5c5476700c"; got != want {
		t.Errorf("IPHash = %q, want %q", got, want)
	}
}

func TestTokenIsNotNormalised(t *testing.T) {
	a := "5B0C6E0D-7F7B-4D5E-9E3A-2C1F8A4B9D10"
	if Author(a) == Author("5b0c6e0d-7f7b-4d5e-9e3a-2c1f8a4b9d10") {
		t.Error("lower-casing the token must change the handle")
	}
	if InstallHash(pepper, a) == InstallHash(pepper, a+" ") {
		t.Error("a trailing space must change the install hash")
	}
	if InstallHash([]byte("other"), a) == InstallHash(pepper, a) {
		t.Error("the pepper must change the install hash")
	}
}

func TestValidToken(t *testing.T) {
	for _, tc := range []struct {
		in   string
		want bool
	}{
		{"5B0C6E0D-7F7B-4D5E-9E3A-2C1F8A4B9D10", true},
		{"abcdefghijklmnop", true},
		{"abcdefghijklmno", false}, // 15
		{"a.b_c-d.e_f-g.h_i-j", true},
		{string(make([]byte, 65)), false},
		{"abcdefghijklmnop ", false},
		{"abcdefghijklmnoé", false},
		{"abcdefghijklmno/", false},
		{"", false},
	} {
		if got := ValidToken(tc.in); got != tc.want {
			t.Errorf("ValidToken(%q) = %v, want %v", tc.in, got, tc.want)
		}
	}
	long := ""
	for i := 0; i < 64; i++ {
		long += "a"
	}
	if !ValidToken(long) || ValidToken(long+"a") {
		t.Error("64 is the longest accepted token")
	}
}

// A subscriber holds a whole /64, so every address in it is one bucket.
func TestIPKeyMasksIPv6(t *testing.T) {
	for _, tc := range []struct{ in, want string }{
		{"203.0.113.7", "203.0.113.7"},
		{"::ffff:203.0.113.7", "203.0.113.7"},
		{"2001:db8:1:2:aaaa:bbbb:cccc:dddd", "2001:db8:1:2::/64"},
		{"2001:0DB8:0001:0002:0000:0000:0000:0001", "2001:db8:1:2::/64"},
		{"2001:db8:1:2::1%eth0", "2001:db8:1:2::/64"},
		{"2001:db8:1:3::1", "2001:db8:1:3::/64"},
		{"not an address", "not an address"},
		{"", ""},
	} {
		if got := IPKey(tc.in); got != tc.want {
			t.Errorf("IPKey(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
	a := IPHash(pepper, "2001:db8:1:2::1")
	if b := IPHash(pepper, "2001:db8:1:2:ffff:ffff:ffff:ffff"); a != b {
		t.Error("two addresses of one /64 must hash alike")
	}
	if b := IPHash(pepper, "2001:db8:1:3::1"); a == b {
		t.Error("another /64 must hash differently")
	}
	// api.md section 7 vector.
	if want := "3ed90d77bfa68a5eb307c474ca0fcdabc8fbcd2ba521e30b1da3fcc880237391"; a != want {
		t.Errorf("IPHash(/64) = %q, want %q", a, want)
	}
}
