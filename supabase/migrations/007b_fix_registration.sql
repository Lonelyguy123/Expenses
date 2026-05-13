-- Patch for 007: replace broken fn_register_user / fn_login_get_key RPCs
-- (those tried to INSERT into auth.users directly which Supabase doesn't allow)
-- Registration and login now go through Supabase Auth API from Python.
-- This migration only adds the missing fn_generate_api_key RPC.

-- Drop old broken RPCs if they exist
drop function if exists public.fn_register_user(text, text, text);
drop function if exists public.fn_login_get_key(text, text);

-- ---------------------------------------------------------------------------
-- RPC: Generate API key for an authenticated user
-- Called server-side after Supabase Auth sign_up / sign_in_with_password
-- ---------------------------------------------------------------------------
create or replace function public.fn_generate_api_key(
  p_user_id uuid,
  p_key_name text default 'Default Key'
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_api_key text;
begin
  v_api_key := 'exp_' || replace(replace(replace(
    encode(gen_random_bytes(32), 'base64'), '+', ''), '/', ''), '=', '');

  insert into public.api_keys (user_id, api_key, key_name)
  values (p_user_id, v_api_key, p_key_name);

  return v_api_key;
end;
$$;

grant execute on function public.fn_generate_api_key(uuid, text) to authenticated;

-- fn_validate_api_key and fn_revoke_api_key from 007 are fine, keep them.
