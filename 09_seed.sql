-- 09_seed.sql  Reference data + one worked example end to end
set search_path to platform, public;

insert into data_classification (code, rank, description) values
  ('PUBLIC',   10, 'No restriction'),
  ('INTERNAL', 20, 'Internal use only'),
  ('PII',      30, 'Personally identifiable information'),
  ('NPI',      40, 'Non-public personal information (GLBA)'),
  ('MNPI',     50, 'Material non-public information');

insert into environment (code, rank, requires_identity_binding, description) values
  ('dev',  10, false, 'Shared platform dev identity permitted'),
  ('qa',   20, true,  'Entra app registration required'),
  ('prod', 30, true,  'Entra app registration required');

-- Worked example -----------------------------------------------------
set local app.actor = 'seed@example.com';

insert into consumer (env, urn, domain, name, display_name, clearance, state, created_by)
values ('prod','urn:awms:prod:consumer:wealth:advisor-desktop','wealth','advisor-desktop',
        'Advisor Desktop','NPI','active','seed@example.com');

insert into consumer_owner (consumer_id, upn, role)
select id, 'owner@example.com', 'accountable_owner' from consumer
where urn = 'urn:awms:prod:consumer:wealth:advisor-desktop';

insert into mcp_server (logical_id, env, urn, domain, name, version, gateway_id, target_name, transport, state, created_by)
values (gen_random_uuid(),'prod','urn:awms:prod:mcp:client:client-server:v1','client','client-server',1,
        'gw-abc123','clientTarget','streamable_http','active','seed@example.com');

insert into tool (logical_id, env, urn, mcp_server_id, domain, name, version,
                  gateway_alias, contract_hash, classification, http_method, http_path, state, created_by)
select gen_random_uuid(),'prod','urn:awms:prod:tool:client:client-profile-get:v2', m.id,
       'client','client-profile-get',2,'clientTarget___getClientProfile',
       'sha256:9f1c2d...','NPI','GET','/clients/{id}','active','seed@example.com'
from mcp_server m where m.urn = 'urn:awms:prod:mcp:client:client-server:v1';

insert into agent (logical_id, env, urn, consumer_id, domain, name, version,
                   entra_app_id, entra_object_id, token_claim, entra_verified_at, state, created_by)
select gen_random_uuid(),'prod','urn:awms:prod:agent:wealth:advisor-summary:v3', c.id,
       'wealth','advisor-summary',3,
       gen_random_uuid(), gen_random_uuid(), 'api://advisor-summary', now(),
       'active','seed@example.com'
from consumer c where c.urn = 'urn:awms:prod:consumer:wealth:advisor-desktop';

-- NPI tool, NPI consumer clearance -> auto-approved, no explicit approver needed.
insert into agent_tool_grant (env, agent_id, tool_id, classification_at_grant,
                              auto_approved, justification, created_by)
select 'prod', a.id, t.id, 'NPI', true, 'Advisor summary needs client profile', 'seed@example.com'
from agent a, tool t
where a.urn = 'urn:awms:prod:agent:wealth:advisor-summary:v3'
  and t.urn = 'urn:awms:prod:tool:client:client-profile-get:v2';

----------------------------------------------------------------------
-- Prompt, guardrail and model route, plus their grants
----------------------------------------------------------------------

insert into prompt (logical_id, env, urn, domain, name, version,
                    bedrock_prompt_arn, bedrock_prompt_version,
                    eval_status, eval_run_id, state, created_by)
values (gen_random_uuid(),'prod','urn:awms:prod:prompt:wealth:advisor-system:v7',
        'wealth','advisor-system',7,
        'arn:aws:bedrock:us-east-1:123456789012:prompt/PROMPT1ABCD','7',
        'passed','eval-2026-09-03-114','active','seed@example.com');

insert into guardrail (logical_id, env, urn, domain, name, version,
                       bedrock_guardrail_id, bedrock_guardrail_version,
                       scope, is_mandatory, state, created_by)
values (gen_random_uuid(),'prod','urn:awms:prod:guardrail:platform:baseline-npi:v4',
        'platform','baseline-npi',4,'gr-9x8y7z','4',
        'platform_baseline', true,'active','seed@example.com'),
       (gen_random_uuid(),'prod','urn:awms:prod:guardrail:wealth:advisor-tone:v1',
        'wealth','advisor-tone',1,'gr-1a2b3c','1',
        'consumer_selectable', false,'active','seed@example.com');

insert into model_route (env, urn, name, provider, upstream_model_id,
                         max_classification, state, created_by)
values ('prod','urn:awms:prod:model:shared:claude-sonnet-4-6',
        'claude-sonnet-4-6','bedrock',
        'anthropic.claude-sonnet-4-6-v1:0','NPI','active','seed@example.com'),
       ('prod','urn:awms:prod:model:shared:claude-haiku-4-5',
        'claude-haiku-4-5','bedrock',
        'anthropic.claude-haiku-4-5-v1:0','INTERNAL','active','seed@example.com');

-- Whole-server MCP grant alongside the fine-grained tool grant.
insert into agent_mcp_grant (env, agent_id, mcp_server_id, approved_by, approved_at,
                             justification, created_by)
select 'prod', a.id, m.id, 'platform.admin@example.com', now(),
       'Advisor summary reaches the client MCP server', 'seed@example.com'
from agent a, mcp_server m
where a.urn = 'urn:awms:prod:agent:wealth:advisor-summary:v3'
  and m.urn = 'urn:awms:prod:mcp:client:client-server:v1';

insert into agent_prompt_grant (env, agent_id, prompt_id, role,
                                approved_by, approved_at, created_by)
select 'prod', a.id, p.id, 'system', 'platform.admin@example.com', now(), 'seed@example.com'
from agent a, prompt p
where a.urn = 'urn:awms:prod:agent:wealth:advisor-summary:v3'
  and p.urn = 'urn:awms:prod:prompt:wealth:advisor-system:v7';

insert into agent_model_grant (env, agent_id, model_route_id, litellm_virtual_key_id,
                               monthly_budget_usd, rpm_limit, tpm_limit,
                               approved_by, approved_at, created_by)
select 'prod', a.id, m.id, 'sk-virtual-advisor-summary', 2500.00, 300, 120000,
       'platform.admin@example.com', now(), 'seed@example.com'
from agent a, model_route m
where a.urn = 'urn:awms:prod:agent:wealth:advisor-summary:v3'
  and m.urn = 'urn:awms:prod:model:shared:claude-sonnet-4-6';

-- Mandatory platform baseline, then the consumer's own selection.
insert into agent_guardrail_binding (env, agent_id, guardrail_id, applied_by, created_by)
select 'prod', a.id, g.id, 'platform', 'seed@example.com'
from agent a, guardrail g
where a.urn = 'urn:awms:prod:agent:wealth:advisor-summary:v3'
  and g.urn = 'urn:awms:prod:guardrail:platform:baseline-npi:v4';

insert into agent_guardrail_binding (env, agent_id, guardrail_id, applied_by, created_by)
select 'prod', a.id, g.id, 'consumer', 'seed@example.com'
from agent a, guardrail g
where a.urn = 'urn:awms:prod:agent:wealth:advisor-summary:v3'
  and g.urn = 'urn:awms:prod:guardrail:wealth:advisor-tone:v1';

----------------------------------------------------------------------
-- A second consumer at INTERNAL clearance, so attestation and the
-- clearance rules have more than one subject to work with.
----------------------------------------------------------------------

insert into consumer (env, urn, domain, name, display_name, clearance, state, created_by)
values ('prod','urn:awms:prod:consumer:ops:service-desk-assist','ops','service-desk-assist',
        'Service Desk Assist','INTERNAL','active','seed@example.com');

insert into consumer_owner (consumer_id, upn, role)
select id, 'ops.owner@example.com', 'accountable_owner' from consumer
where urn = 'urn:awms:prod:consumer:ops:service-desk-assist';

insert into agent (logical_id, env, urn, consumer_id, domain, name, version,
                   entra_app_id, entra_object_id, token_claim, entra_verified_at,
                   state, created_by)
select gen_random_uuid(),'prod','urn:awms:prod:agent:ops:ticket-triage:v1', c.id,
       'ops','ticket-triage',1, gen_random_uuid(), gen_random_uuid(),
       'api://ticket-triage', now(),'active','seed@example.com'
from consumer c where c.urn = 'urn:awms:prod:consumer:ops:service-desk-assist';

insert into agent_model_grant (env, agent_id, model_route_id, litellm_virtual_key_id,
                               monthly_budget_usd, rpm_limit, tpm_limit,
                               approved_by, approved_at, created_by)
select 'prod', a.id, m.id, 'sk-virtual-ticket-triage', 400.00, 120, 40000,
       'platform.admin@example.com', now(), 'seed@example.com'
from agent a, model_route m
where a.urn = 'urn:awms:prod:agent:ops:ticket-triage:v1'
  and m.urn = 'urn:awms:prod:model:shared:claude-haiku-4-5';

insert into agent_guardrail_binding (env, agent_id, guardrail_id, applied_by, created_by)
select 'prod', a.id, g.id, 'platform', 'seed@example.com'
from agent a, guardrail g
where a.urn = 'urn:awms:prod:agent:ops:ticket-triage:v1'
  and g.urn = 'urn:awms:prod:guardrail:platform:baseline-npi:v4';
