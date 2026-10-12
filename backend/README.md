# Toret backend

The community API behind the app: reports, flags, per-fountain summaries and two
pieces of context (weather, SMAT works notices). The contract is
[`../docs/backend/api.md`](../docs/backend/api.md) (machine-readable twin:
[`openapi.yaml`](../docs/backend/openapi.yaml)); where this code and that file
disagree, one of them is a bug.

```
Internet ── torino.deepdive.dev.br ── API Gateway HTTP API ($default, throttled)
                                        └─ api Lambda (Go, arm64) ── DynamoDB (on demand)
EventBridge ── rate(15 minutes) / rate(1 hour) ── ingest Lambda ─┘   └─ SSM /toret/pepper
```

Region `sa-east-1`. No CDN: the source IP API Gateway reports is the real one.
Idle cost is close to zero: on-demand DynamoDB, 14-day log retention, no NAT, no
provisioned anything.

## Layout

| Path | What |
| --- | --- |
| `cmd/api`, `cmd/ingest` | The two Lambda entry points (wiring only) |
| `internal/api` | Routing on API Gateway's `routeKey`, the checks of api.md in their documented order, response shapes |
| `internal/reports` | Report validation, the `NoteFilter` port, summaries (mirrors `CommunitySummary.summarising`) |
| `internal/store` | The `Store` interface, the DynamoDB implementation and an in-memory fake |
| `internal/ratelimit` | Fixed-window counters: install and IP per hour, install per fountain per 20 minutes |
| `internal/handle` | `Visitante XXXXXX`, install hash, IP hash (the test vectors of api.md section 7) |
| `internal/catalogue`, `data/` | The embedded copy of `Shared/Resources/fountains.json`, street index and normaliser |
| `internal/weather`, `internal/smat`, `internal/ingest` | Open-Meteo, SMAT Mappa Cantieri and the scheduled job |
| `internal/httpx`, `internal/fold` | ETag, gzip, error body and messages (pt/en/it); diacritic folding without `x/text` |
| `template.yaml` | SAM template |
| `Makefile` | `help`, `data`, `test`, `validate`, `build`, `pepper`, `deploy`, `outputs` |

`data/fountains.json` is a copy of the app's catalogue (one source of truth). It
is committed so the module builds alone; `make data` refreshes it and a test in
`internal/catalogue` fails if the two differ.

## Develop

```sh
make test       # go vet + go test -race ./...; offline, no AWS
make validate   # cfn-lint on template.yaml (or sam validate --lint with credentials blanked)
```

Needs Go 1.26 or newer (the AWS SDK module requires it; with an older `go`,
`GOTOOLCHAIN=auto` downloads it). Dependencies: the standard library,
AWS SDK for Go v2 (`config`, `service/dynamodb`, `service/ssm`, and its
`smithy-go` core), and `github.com/aws/aws-lambda-go` for the event types and
`lambda.Start`. Nothing else, no web framework.

The whole handler suite runs against `store.Memory`; `store.Dynamo` is tested
against a recording stub (key layout, TTL, every expression through `#names`,
the flag transaction and its cancellation handling).

## Deploy

Deployment is a deliberate step and the only one that touches the account. It
uses whatever AWS credentials the shell has (the default profile; set `PROFILE=`
to pick another).

1. **Pepper, once.** `make pepper` creates the SSM SecureString `/toret/pepper`
   with 32 random bytes and `--no-overwrite`. Never rotate it: every install hash
   (and so every user's ability to delete their reports) derives from it. It is
   not in the repository or the template.
2. **Certificate.** The ISSUED wildcard certificate `*.deepdive.dev.br` in
   `sa-east-1` is looked up by `make deploy` (exactly one match or it stops) and
   passed as the `CertificateArn` parameter. Override with `CERT_ARN=`. It is
   never written to a file.
3. **Upload bucket.** Name one with `S3_BUCKET=<bucket>`, or `RESOLVE_S3=1` to let
   SAM create or reuse its shared `aws-sam-cli-managed-default` stack. That stack
   is outside this one, so the choice is yours; with neither, `sam deploy` stops.
4. `make deploy S3_BUCKET=...` runs the tests, lints, builds and deploys stack
   `toret-api`, showing the change set for confirmation (`CONFIRM=` to skip).
   `SMAT_ENABLED=true` turns the SMAT feature on (default `false`);
   `API_CONCURRENCY=` and `INGEST_CONCURRENCY=` set the reserved concurrency (`-1`: none).

`make deploy` never uses `--guided`, so SAM writes no `samconfig.toml`; the file
and `.aws-sam/` are in `.gitignore` anyway.

### What the stack creates

Only its own things: the DynamoDB table (kept on stack delete and on replacement; a failed first create does not leave it behind), two Lambdas
with explicit roles, two log groups (14 days), the HTTP API with stage `$default`
and a throttle (20 requests/s, burst 40), a regional custom domain, an API
mapping to `$default`, the schedules, and one Route 53 `A` alias for the name.
The alias creation fails, rather than replaces, if the name already has a record.
Nothing refers to any other stack, function or record.

| Parameter | Default | Note |
| --- | --- | --- |
| `CertificateArn` | none | Required; ACM, same region |
| `DomainName` | `torino.deepdive.dev.br` | |
| `HostedZoneId` | the `deepdive.dev.br` zone | An id, not a secret |
| `TableName` | `toret` | |
| `PepperParameterName` | `/toret/pepper` | |
| `SmatEnabled` | `false` | SMAT publishes no licence for this data |
| `ThrottleRate` / `ThrottleBurst` | 20 / 40 | Stage default route settings |
| `ApiReservedConcurrency` / `IngestReservedConcurrency` | 10 / 1 | `-1` leaves it unreserved (needed if the account's concurrency limit is so low that reserving would leave fewer than 10 unreserved) |

The execute-api endpoint is disabled, so only the custom domain reaches the API.
**The API mapping is what makes the custom domain answer**: without it the HTTP
API rejects the host and every route is `403`. Check after a deploy:

```sh
aws apigatewayv2 get-api-mappings --domain-name torino.deepdive.dev.br --region sa-east-1
curl -s https://torino.deepdive.dev.br/v1/health
```

The API role can use the table, read the pepper parameter and write its own log
group. The pepper is a SecureString under the AWS managed key `aws/ssm`, whose
key policy already allows decryption through SSM, so there is no `kms:Decrypt`
grant; if the parameter is ever moved to a customer key, add one scoped with
`kms:ViaService`. The ingest role can only `GetItem`/`PutItem` on the partition
`CONDITIONS`.

## Operating it

- **Moderation** (hide, restore, delete, ban): the runbook in api.md section 9,
  by `aws dynamodb` on the table.
- **SMAT on or off**: redeploy with `SMAT_ENABLED=true|false`. Off means the
  ingest does nothing and `/v1/conditions` answers `{"enabled": false, "items": []}`.
- **Logs**: JSON lines, one per request (route, status, request id, client
  version, milliseconds, error code). Never the install token, the source address
  or a note.
- **Privacy**: DynamoDB holds a salted hash of the install token on each report
  and in counters and flag items, and a salted hash of the source address in
  counters and flag-per-IP items, all with a TTL. Reports are removed 30 days after
  their date. Without the pepper the hashes cannot be reversed or matched.

## Behaviour worth knowing

- Rate limits are fixed windows (clock hour, 20-minute window). A request
  refused by the IP or fountain bucket has already counted against the install
  bucket before it. A retry of a report that was stored is a `200`, checked
  before any counter.
- Lists run on sparse global secondary indexes (hidden reports have no index
  keys), so they are eventually consistent: the client keeps its own just-sent and
  just-deleted reports for 60 seconds (api.md section 5.1).
- `/v1/summaries` is recomputed at most every 20 seconds per warm Lambda and
  covers 36 hours, not the app's 30 days (api.md section 6.3).
- Weather older than 6 hours is `null` and SMAT notices older than 6 hours are
  "no data" (no `fetchedAt`, empty `items`), never "no works".
- SMAT: the Mappa Cantieri service returns the whole province, so only
  `101xx Torino` addresses are kept; the match to fountains is by street name
  and is approximate by construction (api.md section 6.7).
