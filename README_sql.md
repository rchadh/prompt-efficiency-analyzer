# AI Platform Onboarding — Postgres Schema

Validated against PostgreSQL 16. All migrations run clean and the three negative
tests below were confirmed to reject bad data.

## Files, run in this order

| File                 | What it creates                                                                                       |
| -------------------- | ----------------------------------------------------------------------------------------------------- |
| `00_extensions.sql`  | `pgcrypto`, the `platform` schema                                                                     |
| `01_reference.sql`   | `data_classification`, `environment`, `lifecycle_state` domain                                        |
| `02_resources.sql`   | consumer, consumer_owner, agent, mcp_server, tool, prompt, guardrail, model_route                     |
| `03_grants.sql`      | the five agent-to-resource grant tables                                                               |
| `04_governance.sql`  | change_request, change_request_item, clearance trigger, identity gate                                 |
| `05_attestation.sql` | attestation_campaign, attestation_item                                                                |
| `06_history.sql`     | entity_history plus the generic audit trigger                                                         |
| `07_integration.sql` | outbox, entitlement_bundle, reconciliation_finding, projection triggers                               |
| `08_views.sql`       | v_agent_entitlements, v_attestation_feed, v_clearance_violation, v_stale_bundle, v_unbacked_mcp_grant |
| `09_seed.sql`        | reference data plus one worked example end to end                                                     |
| `10_checks.sql`      | sanity queries to run after seeding                                                                   |

## Running it on Windows

From Command Prompt or PowerShell, with psql on your PATH:

```
createdb -h localhost -U postgres aimp

psql -h localhost -U postgres -d aimp -v ON_ERROR_STOP=1 -f sql\00_extensions.sql
psql -h localhost -U postgres -d aimp -v ON_ERROR_STOP=1 -f sql\01_reference.sql
psql -h localhost -U postgres -d aimp -v ON_ERROR_STOP=1 -f sql\02_resources.sql
psql -h localhost -U postgres -d aimp -v ON_ERROR_STOP=1 -f sql\03_grants.sql
psql -h localhost -U postgres -d aimp -v ON_ERROR_STOP=1 -f sql\04_governance.sql
psql -h localhost -U postgres -d aimp -v ON_ERROR_STOP=1 -f sql\05_attestation.sql
psql -h localhost -U postgres -d aimp -v ON_ERROR_STOP=1 -f sql\06_history.sql
psql -h localhost -U postgres -d aimp -v ON_ERROR_STOP=1 -f sql\07_integration.sql
psql -h localhost -U postgres -d aimp -v ON_ERROR_STOP=1 -f sql\08_views.sql
psql -h localhost -U postgres -d aimp -v ON_ERROR_STOP=1 -f sql\09_seed.sql

psql -h localhost -U postgres -d aimp -f sql\10_checks.sql
```

Or all at once in PowerShell:

```
Get-ChildItem sql\*.sql | Sort-Object Name | ForEach-Object {
  psql -h localhost -U postgres -d aimp -v ON_ERROR_STOP=1 -f $_.FullName
}
```

## Things your application must do

**Set the audit actor at the start of every transaction.** The history trigger
reads it. Without this, `changed_by` is null on every row.

```sql
set local app.actor = 'rahul.chadha@ameriprise.com';
```

**Drain the outbox with a worker.** Claim pattern:

```sql
select * from outbox
 where status in ('pending','failed') and available_at <= now()
 order by id limit 50
 for update skip locked;
```

Push to Neptune / LiteLLM / the bundle compiler, then mark `done`. On failure,
increment `attempts`, set `available_at = now() + backoff`, and move to `dead`
after N tries so it shows up on a dashboard instead of retrying forever.

**Verify Entra app registrations against Graph** before setting
`entra_verified_at`. The identity gate refuses to let an agent go active in qa
or prod without it.

## Verified behaviour

Confirmed on a live PostgreSQL 16 instance, schema rebuilt from scratch:

- All ten migrations apply clean in order.
- `v_agent_entitlements` returns 8 rows across all five resource types
  (tool, mcp_server, prompt, model_route, guardrail), matching the 8 active
  grant rows exactly.
- Grant inserts raise the expected outbox events: 8 to `neptune`, 8 to
  `bundle_compiler`, and 2 to `litellm` (one per model grant).
- `v_attestation_feed` groups correctly under each consumer's accountable
  owner, across two consumers at different clearance levels.
- `v_clearance_violation` returns zero rows.
- Every insert lands in `entity_history` with a before/after image.

Negative tests, all correctly rejected:

1. MNPI tool granted to an NPI-clearance consumer with no approver
   -> `Tool classification MNPI exceeds consumer clearance`
2. Two agents sharing one Entra app registration
   -> `duplicate key value violates unique constraint "agent_entra_app_id_uk"`
3. A prod agent set to active with no Entra binding
   -> `Agent cannot become active in prod without an Entra app registration`

## Seed data

`09_seed.sql` builds two consumers so the clearance and attestation logic has
more than one subject:

| Consumer            | Clearance | Agent              | Grants                                                |
| ------------------- | --------- | ------------------ | ----------------------------------------------------- |
| advisor-desktop     | NPI       | advisor-summary v3 | 1 tool, 1 MCP server, 1 prompt, 1 model, 2 guardrails |
| service-desk-assist | INTERNAL  | ticket-triage v1   | 1 model, 1 guardrail                                  |
|                     |           |                    |                                                       |

The advisor agent carries both a fine-grained tool grant and a whole-server MCP
grant, so `v_unbacked_mcp_grant` has something to report on.

## Open decisions this schema does not make for you

- Whether `follow_minor_versions` on a tool grant auto-follows a new tool
  version, and what counts as a breaking contract change.
- Bundle cache TTL and the revocation push path.
- Whether the agent ever holds a LiteLLM virtual key directly, or whether the
  model gateway resolves it server-side from the Entra token. The column
  `agent_model_grant.litellm_virtual_key_id` supports either; the second is
  safer.
