# Community feed: running and moderating the server

The ratings and the "Relatos" feed live on the Toret server: a Go Lambda behind an
API Gateway HTTP API at `https://torino.deepdive.dev.br`, with one DynamoDB table,
in AWS region **eu-south-1** (Milan). The contract is
[`backend/api.md`](backend/api.md); the code and the deploy are in
[`../backend/`](../backend/README.md). There are no accounts: a write carries a
random install token, and the server keeps only a keyed hash of it.

Debug builds keep reports in a file on the device unless launched with
`-toret-api <url>`; Release builds (`make archive`, TestFlight, the App Store)
always talk to the server. Nothing in this file is done from the app: it needs the
owner's AWS credentials.

## 1. Names come from the stack, not from this file

The table, the log groups and the URL are generated, so look them up in the
outputs of the CloudFormation stack (`toret-api`) instead of copying names around:

```sh
export AWS_REGION=eu-south-1
aws cloudformation describe-stacks --stack-name toret-api \
  --query 'Stacks[0].Outputs' --output table
# Url, TableName, ApiLogGroup, IngestLogGroup
export TABLE=$(aws cloudformation describe-stacks --stack-name toret-api \
  --query "Stacks[0].Outputs[?OutputKey=='TableName'].OutputValue" --output text)
```

Account ids, ARNs and the pepper are never committed. The pepper (SSM
`/toret/pepper`) must never be rotated: every install would lose the ability to
delete its own reports.

## 2. Moderation

App Review (guideline 1.2) expects: a way to report content, a way to block
abusers, a filter on what is posted, and a contact. The app has all four: report
and block in each report's "⋯" menu, an on-device filter on the note field (links,
contact details, slurs in pt/it/en) that the server repeats, and
`contato@pedrosantiago.com.br` on the Relatos tab and in the privacy page.

The server adds three things the old setup could not do:

- **Auto-hide.** A report flagged by three distinct installs (and three distinct
  addresses) is removed from every read on its own. Check what was hidden.
- **Rate limits.** One report per install per fountain per 20 minutes, five per
  address per fountain, 40 writes per install and 300 per address an hour, and a
  global ceiling of 200 writes an hour (`429` with `Retry-After`). Details in
  api.md section 4.
- **Expiry.** Every report is deleted 30 days after its date (DynamoDB TTL).

**The runbook** (list what is flagged or hidden, hide, restore, delete for good,
ban an install, ban a source address, open the write breaker) is
**[api.md section 9](backend/api.md)**, written as `aws dynamodb` commands on the
table from the stack outputs. Use it for every moderation action; do not edit the
table by hand any other way.

Answer reports and removal requests within 24 hours where possible; App Review
looks for a stated policy of acting on reports. Keep a short log of what was
removed and why. A removal request arrives by mail: find the report by the handle
the person gives you (`author`, "Visitante XXXXXX"), the fountain and the date,
and hide or delete it as in the runbook. To remove everything an install ever
posted, read its `installHash` from one report and apply the runbook's "hide" to
every `META` item with that hash.

## 3. SMAT works notices: off, and they stay off

`/v1/conditions` can carry SMAT's works orders, but SMAT publishes no licence for
that data and we have no written permission, so the feature is **off**:
`notices.enabled` is `false`, the ingest does nothing and the app shows no notice.
Do not turn it on until SMAT has given permission in writing.

When that day comes, it is a deploy parameter, not a table edit: redeploy the
stack with `SmatEnabled=true` (`make deploy SMAT_ENABLED=true` in `backend/`, or
`--parameter-overrides ... SmatEnabled=true` with `aws cloudformation deploy`, see
"Deploying without the SAM CLI" in the backend README). To turn it back off,
redeploy with `SmatEnabled=false`. Check with
`curl -s https://torino.deepdive.dev.br/v1/conditions`.

## 4. What this setup does not do

- It does not stop a determined person posting from many addresses. The limits
  bound the damage (a flood answers `429` for the rest of the hour while reads
  stay up); the real controls are flags, block, and your hiding or deleting
  records, and banning an address when a flood has one.
- A handle is a label, not a credential (api.md section 7): someone can choose a
  token that shows another person's handle. Ownership is decided by the install
  hash, never by the handle.
- Reports whose `note` fails the filter are hidden by every client even if one got
  into the table by other means, but they stay in the table until you delete them.
- There is no WAF or CDN in front of the API, on purpose: a volumetric flood on a
  route can make that route answer `429` to everyone. See the backend README.
