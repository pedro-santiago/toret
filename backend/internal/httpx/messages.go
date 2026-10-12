package httpx

import "strings"

// Messages are developer-facing (logs, never shown to people). They are keyed
// by "code" or "code/reason", and Accept-Language only picks the column.
var messages = map[string][3]string{ // en, pt, it
	"bad_request":                     {"Malformed request.", "Requisição malformada.", "Richiesta malformata."},
	"invalid_limit":                   {"limit must be an integer of at least 1.", "limit deve ser um inteiro maior ou igual a 1.", "limit deve essere un intero di almeno 1."},
	"install_required":                {"X-Toret-Install is missing or malformed.", "X-Toret-Install ausente ou malformado.", "X-Toret-Install mancante o malformato."},
	"not_owner":                       {"This report belongs to another install.", "Este relato pertence a outra instalação.", "Questa segnalazione appartiene a un'altra installazione."},
	"forbidden":                       {"This install may not write.", "Esta instalação não pode escrever.", "Questa installazione non può scrivere."},
	"unknown_fountain":                {"No such fountain in the catalogue.", "Fonte inexistente no catálogo.", "Fontanella assente dal catalogo."},
	"id_conflict":                     {"This report id belongs to another install.", "Este id de relato pertence a outra instalação.", "Questo id appartiene a un'altra installazione."},
	"body_too_large":                  {"Body is over 4 KiB.", "Corpo maior que 4 KiB.", "Corpo oltre 4 KiB."},
	"unsupported_media_type":          {"Content-Type must be application/json.", "Content-Type deve ser application/json.", "Content-Type deve essere application/json."},
	"empty_report":                    {"A report needs a state or a rating.", "Um relato precisa de um estado ou de uma nota.", "Una segnalazione richiede uno stato o una valutazione."},
	"invalid_id":                      {"id must be a UUID.", "id deve ser um UUID.", "id deve essere un UUID."},
	"invalid_state":                   {"state must be running, weak, dry or unknown.", "state deve ser running, weak, dry ou unknown.", "state deve essere running, weak, dry o unknown."},
	"invalid_rating":                  {"rating must be an integer from 1 to 5.", "rating deve ser um inteiro de 1 a 5.", "rating deve essere un intero da 1 a 5."},
	"invalid_tags":                    {"tags must be at most 3 unique known values.", "tags deve ter no máximo 3 valores conhecidos e únicos.", "tags deve avere al massimo 3 valori noti e unici."},
	"invalid_note":                    {"The note is not acceptable.", "A nota não é aceitável.", "La nota non è accettabile."},
	"invalid_note/too_long":           {"Note is over 280 characters.", "Nota com mais de 280 caracteres.", "Nota oltre 280 caratteri."},
	"invalid_note/control_characters": {"Note contains control characters.", "A nota contém caracteres de controle.", "La nota contiene caratteri di controllo."},
	"invalid_note/objectionable":      {"Note contains objectionable language.", "A nota contém linguagem ofensiva.", "La nota contiene linguaggio offensivo."},
	"invalid_note/contains_contact":   {"Note contains a link, address or phone number.", "A nota contém um link, endereço ou telefone.", "La nota contiene un link, un indirizzo o un numero di telefono."},
	"invalid_date":                    {"date must be within 30 days back and 10 minutes ahead.", "date deve estar entre 30 dias atrás e 10 minutos à frente.", "date deve essere tra 30 giorni fa e 10 minuti avanti."},
	"invalid_reason":                  {"reason must be offensive, spam or false.", "reason deve ser offensive, spam ou false.", "reason deve essere offensive, spam o false."},
	"rate_limited":                    {"Too many writes; try again later.", "Escritas demais; tente de novo mais tarde.", "Troppe scritture; riprova più tardi."},
	"internal":                        {"Internal error.", "Erro interno.", "Errore interno."},
	"unavailable":                     {"Storage is busy; try again shortly.", "Armazenamento ocupado; tente de novo em instantes.", "Archivio occupato; riprova tra poco."},
}

// Lang picks pt, en or it from an Accept-Language header, default en.
func Lang(header string) string {
	for _, part := range strings.Split(header, ",") {
		tag := strings.ToLower(strings.TrimSpace(strings.SplitN(part, ";", 2)[0]))
		switch {
		case strings.HasPrefix(tag, "pt"):
			return "pt"
		case strings.HasPrefix(tag, "it"):
			return "it"
		case strings.HasPrefix(tag, "en"):
			return "en"
		}
	}
	return "en"
}

func message(code, reason, lang string) string {
	m, ok := messages[code+"/"+reason]
	if !ok {
		if m, ok = messages[code]; !ok {
			return code
		}
	}
	switch lang {
	case "pt":
		return m[1]
	case "it":
		return m[2]
	}
	return m[0]
}
