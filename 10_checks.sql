-- 10_checks.sql  Sanity checks to run after seeding
set search_path to platform, public;

-- 1. The grant landed and the outbox picked it up.
select target, event_type, status from outbox order by id;

-- 2. Flattened entitlements for the compiler.
select agent_urn, resource_type, resource_urn, runtime_ref, classification
from v_agent_entitlements;

-- 3. Must return zero rows.
select * from v_clearance_violation;

-- 4. Audit trail exists.
select table_name, operation, changed_by from entity_history order by id;

-- 5. Negative test: MNPI tool for an NPI consumer must be rejected.
--    Expect: ERROR ... exceeds consumer clearance
-- insert into tool (...) values (... classification 'MNPI' ...);
-- insert into agent_tool_grant (env, agent_id, tool_id, classification_at_grant, justification, created_by)
--   values ('prod', <agent>, <mnpi_tool>, 'MNPI', 'test', 'me');

-- 6. Negative test: two agents sharing one Entra app registration must fail.
--    Expect: ERROR duplicate key value violates unique constraint "agent_entra_app_id_uk"
