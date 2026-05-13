-- Fix 1: fn_create_group_invite — replace gen_random_bytes with gen_random_uuid (no pgcrypto)
-- Fix 2: api_keys RLS — allow authenticated users to update their own refresh_token
-- Fix 3: fn_update_api_key_refresh_token — RPC for safe refresh token rotation

-- ---------------------------------------------------------------------------
-- Fix fn_create_group_invite (was using gen_random_bytes which needs pgcrypto)
-- ---------------------------------------------------------------------------
create or replace function public.fn_create_group_invite(
  p_group_id uuid,
  p_expires_in_days integer default 7
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_code text;
  v_days int := greatest(coalesce(nullif(p_expires_in_days, 0), 7), 1);
begin
  if not exists (
    select 1 from public.group_members m
    where m.group_id = p_group_id and m.user_id = auth.uid()
  ) then
    raise exception 'not a member of this group';
  end if;

  -- 12-char code from two UUIDs, no pgcrypto needed
  v_code := lower(substring(replace(gen_random_uuid()::text, '-', '') from 1 for 12));

  insert into public.group_invites (group_id, code, created_by, expires_at)
  values (
    p_group_id,
    v_code,
    auth.uid(),
    now() + (v_days || ' days')::interval
  );

  return v_code;
end;
$$;

grant execute on function public.fn_create_group_invite(uuid, integer) to authenticated;

-- ---------------------------------------------------------------------------
-- Fix api_keys RLS: allow users to update their own refresh_token
-- ---------------------------------------------------------------------------
drop policy if exists api_keys_no_update on public.api_keys;

create policy api_keys_update_own_refresh on public.api_keys
  for update
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------------------
-- RPC: fn_update_api_key_refresh_token
-- Safe refresh token rotation — called by server after each token exchange.
-- Uses security definer so it works even if RLS update policy is restrictive.
-- ---------------------------------------------------------------------------
create or replace function public.fn_update_api_key_refresh_token(
  p_api_key text,
  p_refresh_token text
)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  update public.api_keys
  set refresh_token = p_refresh_token,
      last_used_at = now()
  where api_key = p_api_key
    and is_active = true;
end;
$$;

-- Grant to authenticated AND anon because the server calls this right after
-- refreshing the session (before the new JWT is fully set on the client)
grant execute on function public.fn_update_api_key_refresh_token(text, text) to authenticated, anon;
