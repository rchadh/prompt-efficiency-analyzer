-- 08_views.sql  Read models for the UI, the compiler and the IGA export
set search_path to platform, public;

----------------------------------------------------------------------
-- Everything an agent is currently entitled to, flattened.
----------------------------------------------------------------------
create or replace view v_agent_entitlements as
select a.env, a.id as agent_id, a.urn as agent_urn, c.urn as consumer_urn,
       'tool'::text as resource_type, t.urn as resource_urn, t.id as resource_id,
       t.gateway_alias as runtime_ref, t.contract_hash as pinned_ref,
       g.classification_at_grant as classification,
       g.valid_from, g.expires_at, g.last_attested_at
from agent_tool_grant g
join agent a on a.id = g.agent_id
join consumer c on c.id = a.consumer_id
join tool t on t.id = g.tool_id
where g.revoked_at is null and (g.expires_at is null or g.expires_at > now())

union all
select a.env, a.id, a.urn, c.urn,
       'mcp_server', m.urn, m.id,
       m.target_name, m.gateway_id,
       null, g.valid_from, g.expires_at, g.last_attested_at
from agent_mcp_grant g
join agent a on a.id = g.agent_id
join consumer c on c.id = a.consumer_id
join mcp_server m on m.id = g.mcp_server_id
where g.revoked_at is null and (g.expires_at is null or g.expires_at > now())

union all
select a.env, a.id, a.urn, c.urn,
       'prompt', p.urn, p.id,
       p.bedrock_prompt_arn, p.bedrock_prompt_version,
       null, g.valid_from, null, g.last_attested_at
from agent_prompt_grant g
join agent a on a.id = g.agent_id
join consumer c on c.id = a.consumer_id
join prompt p on p.id = g.prompt_id
where g.revoked_at is null

union all
select a.env, a.id, a.urn, c.urn,
       'model_route', m.urn, m.id,
       m.name, m.upstream_model_id,
       m.max_classification, g.valid_from, null, g.last_attested_at
from agent_model_grant g
join agent a on a.id = g.agent_id
join consumer c on c.id = a.consumer_id
join model_route m on m.id = g.model_route_id
where g.revoked_at is null

union all
select a.env, a.id, a.urn, c.urn,
       'guardrail', gr.urn, gr.id,
       gr.bedrock_guardrail_id, gr.bedrock_guardrail_version,
       null, b.valid_from, null, null
from agent_guardrail_binding b
join agent a on a.id = b.agent_id
join consumer c on c.id = a.consumer_id
join guardrail gr on gr.id = b.guardrail_id
where b.revoked_at is null;

----------------------------------------------------------------------
-- Export feed for the enterprise IGA / attestation tool.
----------------------------------------------------------------------
create or replace view v_attestation_feed as
select e.env,
       e.consumer_urn,
       o.upn as attester_upn,
       e.agent_urn,
       e.resource_type,
       e.resource_urn,
       e.classification,
       e.valid_from as granted_at,
       e.last_attested_at
from v_agent_entitlements e
join consumer c      on c.urn = e.consumer_urn
join consumer_owner o on o.consumer_id = c.id and o.role = 'accountable_owner';

----------------------------------------------------------------------
-- Should always be empty. If it is not, something wrote around the triggers.
----------------------------------------------------------------------
create or replace view v_clearance_violation as
select g.id as grant_id, a.urn as agent_urn, t.urn as tool_urn,
       t.classification as tool_classification,
       c.clearance as consumer_clearance,
       g.approved_by
from agent_tool_grant g
join agent a on a.id = g.agent_id
join consumer c on c.id = a.consumer_id
join tool t on t.id = g.tool_id
join data_classification dct on dct.code = t.classification
join data_classification dcc on dcc.code = c.clearance
where g.revoked_at is null
  and dct.rank > dcc.rank
  and g.approved_by is null;

----------------------------------------------------------------------
-- Agents whose bundle is older than their newest grant change.
----------------------------------------------------------------------
create or replace view v_stale_bundle as
select a.urn as agent_urn, b.bundle_version, b.generated_at, max(g.updated_at) as last_grant_change
from agent a
left join entitlement_bundle b on b.agent_id = a.id and b.is_current
left join agent_tool_grant g   on g.agent_id = a.id
group by a.urn, b.bundle_version, b.generated_at
having b.generated_at is null or b.generated_at < max(g.updated_at);

----------------------------------------------------------------------
-- Whole-server MCP grants that are not backed by explicit tool grants.
-- These are the grants that would bypass the clearance trigger if the
-- gateway interceptor enforces on MCP grants rather than tool grants.
----------------------------------------------------------------------
create or replace view v_unbacked_mcp_grant as
select a.urn as agent_urn, m.urn as mcp_urn, g.approved_by, g.valid_from,
       (select count(*) from tool t where t.mcp_server_id = m.id
          and t.state = 'active') as tools_on_server,
       (select count(*) from agent_tool_grant tg
          join tool t2 on t2.id = tg.tool_id
         where tg.agent_id = a.id and t2.mcp_server_id = m.id
           and tg.revoked_at is null) as tools_granted
from agent_mcp_grant g
join agent a      on a.id = g.agent_id
join mcp_server m on m.id = g.mcp_server_id
where g.revoked_at is null;
