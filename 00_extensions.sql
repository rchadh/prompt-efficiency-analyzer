-- 00_extensions.sql
-- Postgres 13+ has gen_random_uuid() built in. pgcrypto only needed on older versions.
create extension if not exists pgcrypto;

create schema if not exists platform;
set search_path to platform, public;
python -c "import mcp, rank_bm25, yaml, pydantic, pydantic_settings; from mcp.server.mcpserver import MCPServer; print('All packages OK')"
pip show mcp
dir

python -c "import yaml; s=yaml.safe_load(open('specs/client-api.yaml', encoding='utf-8')); print(len(s['paths']), 'paths'); print(sum(1 for p in s['paths'].values() for m in p if m in ('get','post','put','patch','delete')), 'operations'); print(len(s['components']['schemas']), 'schemas')"

pip install openapi-spec-validator
openapi-spec-validator specs\client-api.yaml
{
  "servers": {
    "api-knowledge": {
      "type": "http",
      "url": "http://127.0.0.1:8000/mcp"
    }
  }
}
