-- Add refresh_token column to api_keys so sessions survive server restarts
-- Also update fn_generate_api_key to accept and store refresh token

alter table public.api_keys
  add column if not exists refresh_token text;

-- Updated fn_generate_api_key: stores refresh token alongside api key
create or replace function public.fn_generate_api_key(
  p_user_id uuid,
  p_key_name text default 'Default Key',
  p_refresh_token text default null
)
returns text
language plpgsql
security definer
set search_path = public
as $$
declare
  v_api_key text;
begin
  -- Use gen_random_uuid() — no pgcrypto needed
  v_api_key := 'exp_' || replace(gen_random_uuid()::text, '-', '')
                       || replace(gen_random_uuid()::text, '-', '');

  insert into public.api_keys (user_id, api_key, key_name, refresh_token)
  values (p_user_id, v_api_key, p_key_name, p_refresh_token);

  return v_api_key;
end;
$$;

-- fn_validate_api_key: also returns refresh_token so server can re-auth after restart
create or replace function public.fn_validate_api_key(p_api_key text)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_user_id uuid;
  v_email text;
  v_refresh_token text;
begin
  select ak.user_id, u.email, ak.refresh_token
  into v_user_id, v_email, v_refresh_token
  from public.api_keys ak
  join auth.users u on u.id = ak.user_id
  where ak.api_key = p_api_key
    and ak.is_active = true
    and (ak.expires_at is null or ak.expires_at > now())
    and u.deleted_at is null;

  if not found then
    return jsonb_build_object('status', 'error', 'message', 'Invalid or expired API key');
  end if;

  update public.api_keys set last_used_at = now() where api_key = p_api_key;

  return jsonb_build_object(
    'status', 'success',
    'user_id', v_user_id,
    'email', v_email,
    'refresh_token', v_refresh_token
  );
end;
$$;

grant execute on function public.fn_generate_api_key(uuid, text, text) to authenticated;
grant execute on function public.fn_validate_api_key(text) to anon, authenticated;
