-- 05_attestation.sql  Quarterly entitlement recertification
set search_path to platform, public;

create table attestation_campaign (
  id        uuid primary key default gen_random_uuid(),
  env       text not null references environment(code),
  period    text not null,
  opened_at timestamptz not null default now(),
  due_at    timestamptz not null,
  closed_at timestamptz,
  closed_by text,
  unique (env, period)
);

create table attestation_item (
  id           uuid primary key default gen_random_uuid(),
  campaign_id  uuid not null references attestation_campaign(id) on delete cascade,
  grant_table  text not null
                 check (grant_table in ('agent_tool_grant','agent_mcp_grant',
                                        'agent_prompt_grant','agent_model_grant')),
  grant_id     uuid not null,
  consumer_urn text not null,
  agent_urn    text not null,
  resource_urn text not null,
  classification text,
  attester_upn text not null,
  decision     text check (decision in ('certify','revoke')),
  decided_at   timestamptz,
  note         text,
  unique (campaign_id, grant_table, grant_id)
);

create index attestation_item_attester_idx on attestation_item (attester_upn, campaign_id);
create index attestation_item_pending_idx  on attestation_item (campaign_id) where decision is null;
