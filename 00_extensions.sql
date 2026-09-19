-- 00_extensions.sql
-- Postgres 13+ has gen_random_uuid() built in. pgcrypto only needed on older versions.
create extension if not exists pgcrypto;

create schema if not exists platform;
set search_path to platform, public;
python -c "import mcp, rank_bm25, yaml, pydantic, pydantic_settings; from mcp.server.mcpserver import MCPServer; print('All packages OK')"
pip show mcp
dir
