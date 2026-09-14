-- 03_grants.sql  Grant tables (agent -> resource edges)
set search_path to platform, public;

----------------------------------------------------------------------
-- Agent -> Tool
----------------------------------------------------------------------
create table agent_tool_grant (
  id                     uuid primary key default gen_random_uuid(),
  env                    text not null references environment(code),
  agent_id               uuid not null,
  tool_id                uuid not null,
  change_request_id      uuid,
  classification_at_grant text not null references data_classification(code),
  auto_approved          boolean not null default false,
  approved_by            text,
  approved_at            timestamptz,
  justification          text not null,
  follow_minor_versions  boolean not null default false,
  valid_from             timestamptz not null default now(),
  expires_at             timestamptz,
  revoked_at             timestamptz,
  revoked_by             text,
  revoke_reason          text,
  last_attested_at       timestamptz,
  last_attested_by       text,
  created_at             timestamptz not null default now(),
  created_by             text not null,
  updated_at             timestamptz not null default now(),
  foreign key (agent_id, env) references agent (id, env),
  foreign key (tool_id,  env) references tool  (id, env),
  check (revoked_at is null or revoked_at >= valid_from),
  check (expires_at is null or expires_at >  valid_from)
);

create unique index agent_tool_grant_active_uk
  on agent_tool_grant (agent_id, tool_id) where revoked_at is null;
create index agent_tool_grant_agent_idx on agent_tool_grant (agent_id);
create index agent_tool_grant_tool_idx  on agent_tool_grant (tool_id);

----------------------------------------------------------------------
-- Agent -> MCP server  (whole-server grant; tool grants are finer grained)
----------------------------------------------------------------------
create table agent_mcp_grant (
  id                uuid primary key default gen_random_uuid(),
  env               text not null references environment(code),
  agent_id          uuid not null,
  mcp_server_id     uuid not null,
  change_request_id uuid,
  approved_by       text,
  approved_at       timestamptz,
  justification     text not null,
  valid_from        timestamptz not null default now(),
  expires_at        timestamptz,
  revoked_at        timestamptz,
  revoked_by        text,
  last_attested_at  timestamptz,
  last_attested_by  text,
  created_at        timestamptz not null default now(),
  created_by        text not null,
  foreign key (agent_id,      env) references agent      (id, env),
  foreign key (mcp_server_id, env) references mcp_server (id, env)
);

create unique index agent_mcp_grant_active_uk
  on agent_mcp_grant (agent_id, mcp_server_id) where revoked_at is null;

----------------------------------------------------------------------
-- Agent -> Prompt
----------------------------------------------------------------------
create table agent_prompt_grant (
  id                uuid primary key default gen_random_uuid(),
  env               text not null references environment(code),
  agent_id          uuid not null,
  prompt_id         uuid not null,
  role              text not null default 'system'
                      check (role in ('system','task','tool_selection','other')),
  change_request_id uuid,
  approved_by       text,
  approved_at       timestamptz,
  valid_from        timestamptz not null default now(),
  revoked_at        timestamptz,
  revoked_by        text,
  last_attested_at  timestamptz,
  last_attested_by  text,
  created_at        timestamptz not null default now(),
  created_by        text not null,
  foreign key (agent_id,  env) references agent  (id, env),
  foreign key (prompt_id, env) references prompt (id, env)
);

create unique index agent_prompt_grant_active_uk
  on agent_prompt_grant (agent_id, prompt_id) where revoked_at is null;

----------------------------------------------------------------------
-- Agent -> Model route
----------------------------------------------------------------------
create table agent_model_grant (
  id                    uuid primary key default gen_random_uuid(),
  env                   text not null references environment(code),
  agent_id              uuid not null,
  model_route_id        uuid not null,
  litellm_virtual_key_id text,
  monthly_budget_usd    numeric(12,2),
  rpm_limit             integer,
  tpm_limit             integer,
  change_request_id     uuid,
  approved_by           text,
  approved_at           timestamptz,
  valid_from            timestamptz not null default now(),
  revoked_at            timestamptz,
  revoked_by            text,
  last_attested_at      timestamptz,
  last_attested_by      text,
  created_at            timestamptz not null default now(),
  created_by            text not null,
  foreign key (agent_id,       env) references agent       (id, env),
  foreign key (model_route_id, env) references model_route (id, env)
);

create unique index agent_model_grant_active_uk
  on agent_model_grant (agent_id, model_route_id) where revoked_at is null;

----------------------------------------------------------------------
-- Agent -> Guardrail
----------------------------------------------------------------------
create table agent_guardrail_binding (
  id                uuid primary key default gen_random_uuid(),
  env               text not null references environment(code),
  agent_id          uuid not null,
  guardrail_id      uuid not null,
  applied_by        text not null default 'consumer'
                      check (applied_by in ('platform','consumer')),
  change_request_id uuid,
  valid_from        timestamptz not null default now(),
  revoked_at        timestamptz,
  revoked_by        text,
  created_at        timestamptz not null default now(),
  created_by        text not null,
  foreign key (agent_id,     env) references agent     (id, env),
  foreign key (guardrail_id, env) references guardrail (id, env)
);

create unique index agent_guardrail_binding_active_uk
  on agent_guardrail_binding (agent_id, guardrail_id) where revoked_at is null;
