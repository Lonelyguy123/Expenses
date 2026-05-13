-- Self-service user registration and API key management
-- NOTE: Registration and login are handled via Supabase Auth REST API directly
--       from the Python server (not via SQL RPC).
--       This migration only creates the api_keys table and key-management RPCs.

-- ---------------------------------------------------------------------------
-- API Keys Table
-- ---------------------------------------------------------------------------
create table if not exists public.api_keys (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  api_key text not null unique,
  key_name text not null,
  created_at timestamptz not null default now(),
  last_used_at timestamptz,
  expires_at timestamptz,
  is_active boolean not null default true
);

create index if not exists idx_api_keys_key on public.api_keys(api_key) where is_active = true;
create index if not exists idx_api_keys_user on public.api_keys(user_id);

-- ---------------------------------------------------------------------------
-- RLS for API Keys
-- ---------------------------------------------------------------------------
alter table public.api_keys enable row level security;

create policy api_keys_select_own on public.api_keys
  for select using (auth.uid() = user_id);

create policy api_keys_delete_own on public.api_keys
  for delete using (auth.uid() = user_id);

-- All inserts/updates go through security definer RPCs below
create policy api_keys_no_insert on public.api_keys
  for insert with check (false);

create policy api_keys_no_update on public.api_keys
  for update using (false);

-- ---------------------------------------------------------------------------
-- RPC: Generate API key for a freshly authenticated user
-- Called server-side after successful Supabase Auth sign-up/sign-in
-- ---------------------------------------------------------------------------
create or replace function public.fn_generate_api_key(p_user_id uuid, p_key_name text default 'Default Key')
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_api_key text;
begin
  -- Generate URL-safe random key
  v_api_key := 'exp_' || replace(replace(replace(
    encode(gen_random_bytes(32), 'base64'), '+', ''), '/', ''), '=', '');

  insert into public.api_keys (user_id, api_key, key_name)
  values (p_user_id, v_api_key, p_key_name);

  return v_api_key;
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: Validate API key → return user_id + email
-- Called on every authenticated request
-- ---------------------------------------------------------------------------
create or replace function public.fn_validate_api_key(p_api_key text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_email text;
begin
  select ak.user_id, u.email
  into v_user_id, v_email
  from public.api_keys ak
  join auth.users u on u.id = ak.user_id
  where ak.api_key = p_api_key
    and ak.is_active = true
    and (ak.expires_at is null or ak.expires_at > now())
    and u.deleted_at is null;

  if not found then
    return jsonb_build_object('status', 'error', 'message', 'Invalid or expired API key');
  end if;

  -- Update last used timestamp
  update public.api_keys set last_used_at = now() where api_key = p_api_key;

  return jsonb_build_object('status', 'success', 'user_id', v_user_id, 'email', v_email);
end;
$$;

-- ---------------------------------------------------------------------------
-- RPC: Revoke API key (owner only)
-- ---------------------------------------------------------------------------
create or replace function public.fn_revoke_api_key(p_api_key text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.api_keys
  set is_active = false
  where api_key = p_api_key
    and user_id = auth.uid();

  if not found then
    return jsonb_build_object('status', 'error', 'message', 'API key not found or not owned by you');
  end if;

  return jsonb_build_object('status', 'success', 'message', 'API key revoked successfully');
end;
$$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
grant execute on function public.fn_generate_api_key(uuid, text) to authenticated;
grant execute on function public.fn_validate_api_key(text) to anon, authenticated;
grant execute on function public.fn_revoke_api_key(text) to authenticated;
