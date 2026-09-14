-- 02_resources.sql  Core resource tables
set search_path to platform, public;

----------------------------------------------------------------------
-- Consumer (the onboarded application team)
----------------------------------------------------------------------
create table consumer (
  id           uuid primary key default gen_random_uuid(),
  env          text not null references environment(code),
  urn          text not null unique,
  domain       text not null,
  name         text not null,
  display_name text not null,
  clearance    text not null references data_classification(code),
  cost_center  text,
  state        lifecycle_state not null default 'draft',
  created_at   timestamptz not null default now(),
  created_by   text not null,
  updated_at   timestamptz not null default now(),
  updated_by   text,
  unique (env, domain, name),
  unique (id, env)
);

create table consumer_owner (
  consumer_id     uuid not null references consumer(id) on delete cascade,
  upn             text not null,
  entra_object_id uuid,
  role            text not null check (role in ('accountable_owner','delegate')),
  added_at        timestamptz not null default now(),
  primary key (consumer_id, upn)
);

-- Exactly one accountable owner per consumer; delegates unlimited.
create unique index consumer_accountable_owner_uk
  on consumer_owner (consumer_id) where role = 'accountable_owner';

----------------------------------------------------------------------
-- Agent
----------------------------------------------------------------------
create table agent (
  id                    uuid primary key default gen_random_uuid(),
  logical_id            uuid not null,
  env                   text not null references environment(code),
  urn                   text not null unique,
  consumer_id           uuid not null,
  domain                text not null,
  name                  text not null,
  version               integer not null check (version > 0),
  description           text,
  entra_app_id          uuid,
  entra_object_id       uuid,
  token_claim           text,
  entra_verified_at     timestamptz,
  agentcore_workload_id text,
  agentcore_runtime_arn text,
  state                 lifecycle_state not null default 'draft',
  created_at            timestamptz not null default now(),
  created_by            text not null,
  updated_at            timestamptz not null default now(),
  updated_by            text,
  unique (env, domain, name, version),
  unique (id, env),
  foreign key (consumer_id, env) references consumer (id, env)
);

-- One Entra app registration maps to exactly one agent, ever.
create unique index agent_entra_app_id_uk
  on agent (entra_app_id) where entra_app_id is not null;

create index agent_consumer_idx on agent (consumer_id);
create index agent_logical_idx  on agent (logical_id);

----------------------------------------------------------------------
-- MCP server
----------------------------------------------------------------------
create table mcp_server (
  id           uuid primary key default gen_random_uuid(),
  logical_id   uuid not null,
  env          text not null references environment(code),
  urn          text not null unique,
  domain       text not null,
  name         text not null,
  version      integer not null check (version > 0),
  gateway_id   text,
  gateway_arn  text,
  target_name  text,
  transport    text check (transport in ('streamable_http','sse')),
  owning_team  text,
  state        lifecycle_state not null default 'draft',
  created_at   timestamptz not null default now(),
  created_by   text not null,
  updated_at   timestamptz not null default now(),
  updated_by   text,
  unique (env, domain, name, version),
  unique (id, env)
);

----------------------------------------------------------------------
-- Tool
----------------------------------------------------------------------
create table tool (
  id             uuid primary key default gen_random_uuid(),
  logical_id     uuid not null,
  env            text not null references environment(code),
  urn            text not null unique,
  mcp_server_id  uuid not null,
  domain         text not null,
  name           text not null,
  version        integer not null check (version > 0),
  gateway_alias  text not null,
  contract_hash  text not null,
  classification text not null references data_classification(code),
  backing_api    text,
  http_method    text,
  http_path      text,
  description    text,
  state          lifecycle_state not null default 'draft',
  created_at     timestamptz not null default now(),
  created_by     text not null,
  updated_at     timestamptz not null default now(),
  updated_by     text,
  unique (env, domain, name, version),
  unique (env, gateway_alias),
  unique (id, env),
  foreign key (mcp_server_id, env) references mcp_server (id, env)
);

create index tool_mcp_idx            on tool (mcp_server_id);
create index tool_classification_idx on tool (classification);
create index tool_logical_idx        on tool (logical_id);

----------------------------------------------------------------------
-- Prompt  (Bedrock Prompt Management, pinned version)
----------------------------------------------------------------------
create table prompt (
  id                     uuid primary key default gen_random_uuid(),
  logical_id             uuid not null,
  env                    text not null references environment(code),
  urn                    text not null unique,
  domain                 text not null,
  name                   text not null,
  version                integer not null check (version > 0),
  bedrock_prompt_arn     text not null,
  bedrock_prompt_version text not null,
  eval_status            text not null default 'pending'
                           check (eval_status in ('pending','passed','failed','waived')),
  eval_run_id            text,
  state                  lifecycle_state not null default 'draft',
  created_at             timestamptz not null default now(),
  created_by             text not null,
  updated_at             timestamptz not null default now(),
  updated_by             text,
  check (bedrock_prompt_version <> 'DRAFT'),
  unique (env, domain, name, version),
  unique (env, bedrock_prompt_arn, bedrock_prompt_version),
  unique (id, env)
);

----------------------------------------------------------------------
-- Guardrail  (Bedrock Guardrails, pinned version)
----------------------------------------------------------------------
create table guardrail (
  id                        uuid primary key default gen_random_uuid(),
  logical_id                uuid not null,
  env                       text not null references environment(code),
  urn                       text not null unique,
  domain                    text not null,
  name                      text not null,
  version                   integer not null check (version > 0),
  bedrock_guardrail_id      text not null,
  bedrock_guardrail_version text not null,
  scope                     text not null
                              check (scope in ('platform_baseline','consumer_selectable')),
  is_mandatory              boolean not null default false,
  state                     lifecycle_state not null default 'draft',
  created_at                timestamptz not null default now(),
  created_by                text not null,
  updated_at                timestamptz not null default now(),
  updated_by                text,
  check (bedrock_guardrail_version <> 'DRAFT'),
  check (scope <> 'platform_baseline' or is_mandatory),
  unique (env, domain, name, version),
  unique (id, env)
);

----------------------------------------------------------------------
-- Model route  (what LiteLLM exposes)
----------------------------------------------------------------------
create table model_route (
  id                 uuid primary key default gen_random_uuid(),
  env                text not null references environment(code),
  urn                text not null unique,
  name               text not null,
  provider           text not null,
  upstream_model_id  text not null,
  max_classification text not null references data_classification(code),
  state              lifecycle_state not null default 'draft',
  created_at         timestamptz not null default now(),
  created_by         text not null,
  updated_at         timestamptz not null default now(),
  updated_by         text,
  unique (env, name),
  unique (id, env)
);
