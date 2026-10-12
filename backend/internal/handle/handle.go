// Package handle derives the three identifiers the API builds from an install
// token and a source address (docs/backend/api.md, section 7).
package handle

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/hex"
	"fmt"
)

// Author is the public handle, identical to AuthorHandle.make(from:) in the app:
// "Visitante " + upper-case hex of the first three bytes of
// SHA-256("toret.author." + token). The token is used byte for byte.
func Author(token string) string {
	sum := sha256.Sum256([]byte("toret.author." + token))
	return fmt.Sprintf("Visitante %X", sum[:3])
}

// InstallHash is what the server stores to recognise an install:
// lower-case hex HMAC-SHA256(pepper, "toret.install.v1:" + token).
func InstallHash(pepper []byte, token string) string {
	return mac(pepper, "toret.install.v1:"+token)
}

// IPHash is used for rate limiting and flag de-duplication only:
// lower-case hex HMAC-SHA256(pepper, "toret.ip.v1:" + ip).
func IPHash(pepper []byte, ip string) string {
	return mac(pepper, "toret.ip.v1:"+ip)
}

func mac(key []byte, msg string) string {
	m := hmac.New(sha256.New, key)
	m.Write([]byte(msg))
	return hex.EncodeToString(m.Sum(nil))
}

// ValidToken reports whether s is an acceptable X-Toret-Install value: 16 to 64
// characters from [A-Za-z0-9._-]. It never normalises.
func ValidToken(s string) bool {
	if len(s) < 16 || len(s) > 64 {
		return false
	}
	for i := 0; i < len(s); i++ {
		c := s[i]
		switch {
		case c >= 'a' && c <= 'z', c >= 'A' && c <= 'Z', c >= '0' && c <= '9', c == '.', c == '_', c == '-':
		default:
			return false
		}
	}
	return true
}
