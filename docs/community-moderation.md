# Community feed: one-time setup and moderation

The ratings and the "Relatos" feed live in CloudKit's **public database** of the
container `iCloud.br.tec.nuance.toret`. There is no server of our own. Nothing in
this file can be done from code: it needs the owner's Apple Developer account.

Builds without the iCloud entitlement (Debug, Personal-team installs) never touch
CloudKit; they keep reports in a file on the device. Only **Release** builds
(`make archive`, TestFlight, the App Store) are signed with the container.

## 1. Create the container (once)

1. developer.apple.com → Certificates, Identifiers & Profiles → **Identifiers** →
   iCloud Containers → `+` → identifier `iCloud.br.tec.nuance.toret`.
2. Identifiers → App IDs → `br.tec.nuance.toret` → enable **iCloud** with
   **CloudKit**, and tick that container.
3. The group `group.br.tec.nuance.toret` must already be on both App IDs
   (`br.tec.nuance.toret` and `br.tec.nuance.toret.widgets`); see `DISTRIBUICAO.md`.

Archiving with `-allowProvisioningUpdates` and an Admin account signed in to Xcode
can also register the container; the API key (App Manager) cannot.

## 2. Create the schema in Development

Record types are created on first save from a development-signed build, or by hand
in the CloudKit Dashboard → container → **Development** → Schema → Record Types.

**`Report`**

| Field       | Type          |
| ----------- | ------------- |
| `fountainID`| String        |
| `state`     | String        |
| `rating`    | Int(64)       |
| `tags`      | String (list) |
| `note`      | String        |
| `date`      | Date/Time     |
| `author`    | String        |

**`Flag`**

| Field      | Type      |
| ---------- | --------- |
| `reportID` | String    |
| `reason`   | String    |
| `date`     | Date/Time |

### Indexes (Dashboard → Schema → Indexes)

CloudKit refuses a query on a field that is not indexed, so these are required:

- `Report`: `recordName` — **Queryable**
- `Report`: `fountainID` — **Queryable**
- `Report`: `date` — **Queryable** and **Sortable**
- `Flag`: `recordName` — **Queryable** (so you can list flags in the Dashboard)

### Security roles (Dashboard → Schema → Security Roles)

- `Report`: **World** — Read. **Authenticated** — Create. **Creator** — Write
  (this is what lets a person edit/delete only their own report). Nobody else may write.
- `Flag`: **Authenticated** — Create only. Not readable by World; only you read
  flags (as owner, in the Dashboard).

## 3. Deploy the schema to Production (before the first TestFlight/App Store build)

Dashboard → **Deploy Schema Changes…** (Development → Production). The Release
build talks to **Production**; an undeployed schema means every query fails and the
feed stays empty. Redo this whenever a field or an index is added.

## 4. Moderation

App Review (guideline 1.2) expects: a way to report content, a way to block
abusers, a filter on what is posted, and a contact. The app has all four:
report and block in each report's "⋯" menu, an on-device filter on the note field
(links, contact details, slurs in pt/it/en), and `contato@pedrosantiago.com.br` on
the Relatos tab and in the privacy page.

**Reviewing flags**

1. CloudKit Dashboard → Data → **Production** → Public Database → record type `Flag`
   → Query Records (sort by `date`).
2. Each flag holds `reportID` and `reason` (`offensive`, `spam`, `false`).
3. Look the report up: record type `Report`, Query by `recordName == <reportID>`.
4. To remove it, **delete the `Report` record**. The app drops it from every device at
   the next refresh. To remove an author's content, delete every `Report` with the
   same `author` handle. (Handles are anonymous; there is no way to contact an author.)
5. Answer within 24 hours where possible; App Review looks for a stated policy of acting
   on reports. Keep a short log of what was removed and why.

Also expect mail at the contact address asking for removal of a report: look it up the
same way.

## 5. Things this setup does not do

- It does not stop a determined person posting from several iCloud accounts. The
  per-fountain rate limit (30 min) and the filter are client-side; the real controls
  are flags, block and your deleting records.
- Reports whose `note` fails the filter are hidden by every client even if one got into
  the database by other means, but they stay in the database until you delete them.
