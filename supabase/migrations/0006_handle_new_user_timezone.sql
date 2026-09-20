-- Migration 0006: Safe timezone handling in handle_new_user trigger
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_timezone text;
  v_raw_tz text;
begin
  v_raw_tz := new.raw_user_meta_data->>'timezone';

  if v_raw_tz is not null and exists (
    select 1 from pg_catalog.pg_timezone_names where name = v_raw_tz
  ) then
    v_timezone := v_raw_tz;
  else
    v_timezone := 'Asia/Bangkok';
  end if;

  insert into public.profiles (id, display_name, timezone)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', nullif(split_part(new.email, '@', 1), ''), 'Guest'),
    v_timezone
  );
  return new;
end;
$$;

revoke execute on function public.handle_new_user() from public, anon, authenticated;
