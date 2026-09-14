-- 04_governance.sql  Change requests, approvals, maker-checker
set search_path to platform, public;

create table change_request (
  id            uuid primary key default gen_random_uuid(),
  env           text not null references environment(code),
  consumer_id   uuid not null,
  type          text not null check (type in ('onboard','modify','offboard')),
  status        text not null default 'draft'
                  check (status in ('draft','submitted','approved','rejected','applied','failed')),
  summary       text not null,
  requested_by  text not null,
  requested_at  timestamptz not null default now(),
  submitted_at  timestamptz,
  decided_by    text,
  decided_at    timestamptz,
  decision_note text,
  applied_at    timestamptz,
  failure_note  text,
  foreign key (consumer_id, env) references consumer (id, env),
  -- maker-checker: the requester can never be the approver
  check (requested_by is distinct from decided_by),
  check (status <> 'approved' or decided_by is not null)
);

create index change_request_status_idx   on change_request (status);
create index change_request_consumer_idx on change_request (consumer_id);

create table change_request_item (
  id                        uuid primary key default gen_random_uuid(),
  change_request_id         uuid not null references change_request(id) on delete cascade,
  seq                       integer not null,
  action                    text not null check (action in ('create','update','grant','revoke')),
  resource_type             text not null
                              check (resource_type in ('consumer','agent','mcp_server','tool',
                                                       'prompt','model_route','guardrail')),
  resource_urn              text,
  agent_urn                 text,
  payload                   jsonb not null default '{}'::jsonb,
  requires_elevated_approval boolean not null default false,
  applied_row_id            uuid,
  unique (change_request_id, seq)
);

-- Add the deferred FKs from grant tables now that change_request exists.
alter table agent_tool_grant        add constraint agent_tool_grant_cr_fk        foreign key (change_request_id) references change_request(id);
alter table agent_mcp_grant         add constraint agent_mcp_grant_cr_fk         foreign key (change_request_id) references change_request(id);
alter table agent_prompt_grant      add constraint agent_prompt_grant_cr_fk      foreign key (change_request_id) references change_request(id);
alter table agent_model_grant       add constraint agent_model_grant_cr_fk       foreign key (change_request_id) references change_request(id);
alter table agent_guardrail_binding add constraint agent_guardrail_binding_cr_fk foreign key (change_request_id) references change_request(id);

----------------------------------------------------------------------
-- Clearance enforcement: a tool above the consumer's clearance needs
-- an explicit approver. Runs on every write, not just via the UI.
----------------------------------------------------------------------
create or replace function enforce_tool_clearance() returns trigger as $$
declare
  v_tool_rank     smallint;
  v_tool_class    text;
  v_consumer_rank smallint;
begin
  select dc.rank, t.classification
    into v_tool_rank, v_tool_class
  from tool t
  join data_classification dc on dc.code = t.classification
  where t.id = new.tool_id;

  select dc.rank
    into v_consumer_rank
  from agent a
  join consumer c            on c.id  = a.consumer_id
  join data_classification dc on dc.code = c.clearance
  where a.id = new.agent_id;

  new.classification_at_grant := v_tool_class;

  if v_tool_rank > v_consumer_rank then
    if new.approved_by is null then
      raise exception
        'Tool classification % exceeds consumer clearance; explicit approval required',
        v_tool_class;
    end if;
    new.auto_approved := false;
  end if;

  return new;
end;
$$ language plpgsql;

create trigger agent_tool_grant_clearance
  before insert or update on agent_tool_grant
  for each row execute function enforce_tool_clearance();

----------------------------------------------------------------------
-- Identity gate: an agent cannot go active without an Entra binding
-- in environments that require one.
----------------------------------------------------------------------
create or replace function enforce_agent_identity() returns trigger as $$
declare
  v_required boolean;
begin
  if new.state <> 'active' then
    return new;
  end if;

  select requires_identity_binding into v_required
  from environment where code = new.env;

  if v_required and new.entra_app_id is null then
    raise exception 'Agent cannot become active in % without an Entra app registration', new.env;
  end if;

  if v_required and new.entra_verified_at is null then
    raise exception 'Entra app registration for agent % has not been verified against Graph', new.urn;
  end if;

  return new;
end;
$$ language plpgsql;

create trigger agent_identity_gate
  before insert or update on agent
  for each row execute function enforce_agent_identity();
