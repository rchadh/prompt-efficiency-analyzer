-- 01_reference.sql  Reference / lookup tables
set search_path to platform, public;

create table data_classification (
  code        text primary key,
  rank        smallint not null unique,
  description text not null
);

create table environment (
  code                      text primary key,
  rank                      smallint not null unique,
  requires_identity_binding boolean  not null default true,
  description               text
);

-- Allowed lifecycle states, reused by check constraints below.
create domain lifecycle_state as text
  check (value in ('draft','identity_pending','provisioning','active','suspended','offboarded'));
