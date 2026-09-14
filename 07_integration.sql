-- 07_integration.sql  Outbox, bundles, reconciliation
set search_path to platform, public;

create table outbox (
  id              bigserial primary key,
  aggregate_type  text not null,
  aggregate_id    uuid not null,
  target          text not null check (target in ('neptune','litellm','bundle_compiler')),
  event_type      text not null,
  payload         jsonb not null,
  idempotency_key text not null,
  status          text not null default 'pending'
                    check (status in ('pending','in_flight','done','failed','dead')),
  attempts        int  not null default 0,
  last_error      text,
  available_at    timestamptz not null default now(),
  created_at      timestamptz not null default now(),
  completed_at    timestamptz,
  unique (target, idempotency_key)
);

create index outbox_claim_idx
  on outbox (target, available_at)
  where status in ('pending','failed');

-- Worker claim pattern:
--   select * from outbox
--    where status in ('pending','failed') and available_at <= now()
--    order by id limit 50
--    for update skip locked;

----------------------------------------------------------------------
-- Emit projection events inside the same transaction as the change.
-- txid_current() in the key collapses many grants changed in one
-- transaction into a single recompile event.
----------------------------------------------------------------------
create or replace function emit_agent_projection() returns trigger as $$
declare
  v_agent uuid := coalesce(new.agent_id, old.agent_id);
  v_row   uuid := coalesce(new.id, old.id);
begin
  insert into outbox (aggregate_type, aggregate_id, target, event_type, payload, idempotency_key)
  values (
    'agent', v_agent, 'neptune', 'grant_changed',
    jsonb_build_object('agent_id', v_agent, 'grant_table', tg_table_name,
                       'grant_id', v_row, 'op', tg_op),
    tg_table_name || ':' || v_row || ':' || txid_current()
  )
  on conflict (target, idempotency_key) do nothing;

  insert into outbox (aggregate_type, aggregate_id, target, event_type, payload, idempotency_key)
  values (
    'agent', v_agent, 'bundle_compiler', 'recompile',
    jsonb_build_object('agent_id', v_agent),
    'bundle:' || v_agent || ':' || txid_current()
  )
  on conflict (target, idempotency_key) do nothing;

  return null;
end;
$$ language plpgsql;

create trigger agent_tool_grant_outbox
  after insert or update or delete on agent_tool_grant
  for each row execute function emit_agent_projection();
create trigger agent_mcp_grant_outbox
  after insert or update or delete on agent_mcp_grant
  for each row execute function emit_agent_projection();
create trigger agent_prompt_grant_outbox
  after insert or update or delete on agent_prompt_grant
  for each row execute function emit_agent_projection();
create trigger agent_guardrail_binding_outbox
  after insert or update or delete on agent_guardrail_binding
  for each row execute function emit_agent_projection();

-- Model grants additionally project to LiteLLM, so they get their own
-- function that emits all three events.
create or replace function emit_model_projection() returns trigger as $$
declare
  v_agent uuid := coalesce(new.agent_id, old.agent_id);
  v_row   uuid := coalesce(new.id, old.id);
begin
  insert into outbox (aggregate_type, aggregate_id, target, event_type, payload, idempotency_key)
  values
    ('agent', v_agent, 'neptune', 'grant_changed',
     jsonb_build_object('agent_id', v_agent, 'grant_table', tg_table_name,
                        'grant_id', v_row, 'op', tg_op),
     tg_table_name || ':' || v_row || ':' || txid_current()),
    ('agent', v_agent, 'bundle_compiler', 'recompile',
     jsonb_build_object('agent_id', v_agent),
     'bundle:' || v_agent || ':' || txid_current()),
    ('agent', v_agent, 'litellm', 'model_access_changed',
     jsonb_build_object('agent_id', v_agent, 'grant_id', v_row, 'op', tg_op),
     'litellm:' || v_agent || ':' || txid_current())
  on conflict (target, idempotency_key) do nothing;
  return null;
end;
$$ language plpgsql;

create trigger agent_model_grant_outbox
  after insert or update or delete on agent_model_grant
  for each row execute function emit_model_projection();

----------------------------------------------------------------------
-- Compiled entitlement bundles
----------------------------------------------------------------------
create table entitlement_bundle (
  id             uuid primary key default gen_random_uuid(),
  env            text not null references environment(code),
  agent_id       uuid not null,
  bundle_version bigint not null,
  content_hash   text not null,
  s3_uri         text not null,
  kms_key_arn    text,
  grant_count    integer not null default 0,
  generated_at   timestamptz not null default now(),
  is_current     boolean not null default true,
  foreign key (agent_id, env) references agent (id, env),
  unique (agent_id, bundle_version)
);

create unique index entitlement_bundle_current_uk
  on entitlement_bundle (agent_id) where is_current;

----------------------------------------------------------------------
-- Nightly drift detection against Neptune and LiteLLM
----------------------------------------------------------------------
create table reconciliation_finding (
  id             bigserial primary key,
  run_at         timestamptz not null default now(),
  target         text not null check (target in ('neptune','litellm')),
  finding_type   text not null
                   check (finding_type in ('missing_in_target','extra_in_target','attribute_mismatch')),
  aggregate_type text not null,
  aggregate_id   uuid,
  detail         jsonb not null,
  resolved_at    timestamptz,
  resolved_by    text
);

create index reconciliation_open_idx on reconciliation_finding (run_at desc) where resolved_at is null;
