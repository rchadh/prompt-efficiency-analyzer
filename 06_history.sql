-- 06_history.sql  Generic before/after audit trail
set search_path to platform, public;

create table entity_history (
  id         bigserial primary key,
  table_name text not null,
  row_id     uuid not null,
  operation  text not null check (operation in ('INSERT','UPDATE','DELETE')),
  changed_at timestamptz not null default now(),
  changed_by text,
  old_row    jsonb,
  new_row    jsonb
);

create index entity_history_row_idx  on entity_history (table_name, row_id, changed_at desc);
create index entity_history_time_idx on entity_history (changed_at desc);

create or replace function log_history() returns trigger as $$
begin
  insert into entity_history (table_name, row_id, operation, changed_by, old_row, new_row)
  values (
    tg_table_name,
    case when tg_op = 'DELETE' then old.id else new.id end,
    tg_op,
    current_setting('app.actor', true),
    case when tg_op = 'INSERT' then null else to_jsonb(old) end,
    case when tg_op = 'DELETE' then null else to_jsonb(new) end
  );
  return case when tg_op = 'DELETE' then old else new end;
end;
$$ language plpgsql;

-- Attach to every resource and grant table.
do $$
declare t text;
begin
  foreach t in array array[
    'consumer','agent','mcp_server','tool','prompt','guardrail','model_route',
    'agent_tool_grant','agent_mcp_grant','agent_prompt_grant',
    'agent_model_grant','agent_guardrail_binding',
    'change_request'
  ] loop
    execute format(
      'create trigger %I_history after insert or update or delete on %I
       for each row execute function log_history()', t, t);
  end loop;
end $$;
