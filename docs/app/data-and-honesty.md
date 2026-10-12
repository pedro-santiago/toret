# Data and honesty

**The rule:** the app has no live per-fountain data. Only a dated community report may
make it say a fountain is running, weak or dry, and only for 36 hours. Everything else
is context, with its source and age, or it is not shown.

The server repeats the rule on the wire ([../backend/api.md](../backend/api.md), section 1):
weather and works notices never carry a field worded like a water state.

## Where each datum comes from

| Datum | Source | Freshness | Shown where | Allowed claim |
| --- | --- | --- | --- | --- |
| Fountain position, kind, name, plate number, wheelchair, bottle, dogs, seasonal, last-checked date | OpenStreetMap, bundled in `Shared/Resources/fountains.json` (ODbL) | As of the last `tools/build-catalogue.py` run; changes ship with an app update | Everywhere | "Position from OpenStreetMap." Attribute as "(c) OpenStreetMap contributors (ODbL)". A missing tag is shown as "Não informado", never as "no". |
| Water state (running / weak / dry) | Community reports made with the app, via our server | A report is believed for 36 h (`CommunitySummary.freshness`), then the state returns to "no recent report" | Pin mark, row, detail sentence, notification body | "Água corrente, relato há 2 h". Never without the report's age. |
| "Sem relato recente" | Absence of a fresh report | n/a | Same places | "Nobody has said recently." Not "unknown whether it works", not "probably fine". |
| Rating (1-5), tags, notes | Community reports | Reports older than 30 days leave the feed (`Community.feedWindow`) | Detail, Relatos | An average of what people said, with the count: "4,6 - 12 avaliações". |
| Weather: temperature and apparent temperature | Open-Meteo, fetched by our server for one point in central Turin (CC BY 4.0) | Refreshed at most every 15 min; the app hides it once `observedAt` is over 3 h old | One line on Perto | "Turim agora: 24 °C, sensação 25 °C · Open-Meteo, 14:05", plus "Dia quente: leve água." when apparent temperature or the day's maximum is 30 or more. Says nothing about any fountain. |
| SMAT works notices | SMAT "Mappa Cantieri" via our server; **OFF** | Would require a fetch under 6 h old | Would appear on Detail | Nothing today. See below. |
| Distance | Straight-line geodesic distance from the user (or from the anchor) to the fountain, in metres | Re-measured on every fix of 10 m or more | Everywhere | "84 m" as the crow flies. Not a walking distance. |
| Walking minutes | Distance / 80 m per minute, minimum 1 | Same | Detail, Perto, Live Activity | An estimate. The route screen uses MapKit's route and distance once it answers. |
| Bearing | Forward azimuth, user to fountain, degrees clockwise from north | Same | Compass, widgets, Live Activity | A direction. The compass spoken form is relative to landmarks: "Olhe entre a Mole Antonelliana e a Basilica di Superga". |
| Heading (which way the phone faces) | Magnetometer, true heading when available | Live; used only if accuracy is 35 degrees or better | Compass dial, Live Activity needle | The dial turns only with a trustworthy heading and a real fix; otherwise it is a north-up chart and says so. |
| User position | Device GPS | Live; the fix the widgets use is discarded after 6 h | Distances everywhere, the user dot on the map | Never sent to the Toret server (reports carry no position). The app writes a bare fix into the on-device app group so widgets can measure, and the walk route asks Apple MapKit for walking directions from it. Ajustes says: "A sua localização fica no aparelho". |

## The four states

`WaterState` in `Shared/Model/Fountain.swift`; shapes from `StateMark`
(`Shared/DesignSystem/Poster.swift`).

| State | Mark | pt-BR label | en | it |
| --- | --- | --- | --- | --- |
| `running` | blue circle | Água corrente | Water running | Acqua che scorre |
| `weak` | yellow half-disc | Fluxo fraco | Weak flow | Flusso debole |
| `dry` | red triangle | Sem água | No water | Senz’acqua |
| `unknown` | empty ring | Sem relato recente | No recent report | Nessuna segnalazione recente |

Only `running`, `weak` and `dry` can be reported; `unknown` is the absence of a report
(`WaterState.reportable`). A rating given without a state does not reset "running" to
"unknown" (`CommunitySummary.summarising` looks at the newest report that *has* a
state). `dry` is the only state treated as "not worth a walk": the widget candidates,
`nearestUsable` (used by "route to nearest") and the proximity geofences skip dry
fountains; an unreported one is still the best guess within reach (`WaterState.isUsable`).

### The "sem relato recente" rule

- It is the default for every fountain on a fresh install: 723 of 723.
- It is what a stale report becomes after 36 hours: yesterday's "dry" is not believed
  today, and last week's "running" says nothing about now.
- The mark for it is a calm empty ring, not a warning.
- When there *is* an old report, the sentence says so: "Sem relato recente. Último relato
  há 3 dias" (`CommunitySummary.sentence`).
- Widgets, controls, Siri and the Live Activity never carry community summaries (the
  extension does not receive them), so their caption is "kind - neighbourhood", never a
  water state (`Fountain.widgetCaption`).

## Context data

### Weather (Open-Meteo)

Shown as one quiet line on Perto (`WeatherLine`), always with source and time. If the
reading is over 3 hours old, or the server is unreachable and the disk copy is old, the
line is simply absent. It is credited in Ajustes ("Dados do tempo por Open-Meteo.com
(CC BY 4.0)"). Open-Meteo's free API is for non-commercial use: if the app ever earns
money, a paid plan comes first ([`DATA-LICENSE.md`](../../DATA-LICENSE.md)).

### SMAT works notices: implemented, OFF

The code can show "A SMAT lista uma obra perto de <rua>, iniciada em <data>. O
abastecimento próximo pode ser afetado. Fonte: SMAT, <hora>" on a fountain's page
(`WorksNotices`, `Conditions.notices(for:)`). It is off because **SMAT publishes no
licence for its works data and there is no permission**. The server flag
(`SMAT_ENABLED` / `SmatEnabled`) is `false`, `notices.enabled` comes back `false`, and
the app shows nothing. It stays off until SMAT gives written permission
([`DATA-LICENSE.md`](../../DATA-LICENSE.md), [`DISTRIBUICAO.md`](../../DISTRIBUICAO.md)).
Even if switched on, a street name only matches approximately, and no data is never
shown as "no works".

## What the app never says

- That water is running, weak or dry without a report under 36 hours old.
- That a fountain is "safe", "potable" or "tested". The footnote on every detail page:
  "O estado da água vem só dos relatos da comunidade; o Toret não mede nem garante a água."
- Anything about water quality, from weather or from anyone's tags. Tags like "Limpa" or
  "Suja" are a person's words, shown as theirs.
- A distance from the wrong place without a sentence explaining it.
- "No" for a feature OpenStreetMap does not mention: it says "Não informado".
- A walking time as an exact figure (it is a pace estimate).
- A water state in a notification unless one exists: the proximity alert says
  "Relato recente: ..." only when a fresh report does.

## Privacy

No account, no advertising identifier, no tracking. A report carries which fountain,
when, the state, rating, tags, note (140 characters) and the author's anonymous handle.
It carries no position. The server keeps only a keyed hash of the install token and
deletes reports after 30 days. Pages: [../privacy/index.html](../privacy/index.html);
moderation and takedown: [../community-moderation.md](../community-moderation.md).
