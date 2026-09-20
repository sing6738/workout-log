-- Create profile on signup (also fires for anonymous users if demo mode uses them)
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.profiles (id, display_name)
  values (
    new.id,
    coalesce(new.raw_user_meta_data->>'name', nullif(split_part(new.email, '@', 1), ''), 'Guest')
  );
  return new;
end;
$$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

revoke execute on function public.handle_new_user() from public, anon, authenticated;

-- Atomic save/update of a workout with all its sets.
-- payload: { id?, date?, notes?, sets: [{ id, exercise_id, exercise_order, set_number,
--            set_type, reps, weight_kg, rpe }] }   (every set MUST have a client-generated id)
create or replace function public.save_workout(payload jsonb)
returns uuid
language plpgsql
security invoker            -- RLS applies as the calling user
set search_path = ''
as $$
declare
  v_user_id uuid := (select auth.uid());
  v_workout_id uuid;
begin
  if v_user_id is null then
    raise exception 'Not authenticated' using errcode = '28000';
  end if;

  if jsonb_typeof(payload->'sets') is distinct from 'array' then
    raise exception 'payload.sets must be an array';
  end if;

  if exists (
    select 1 from jsonb_to_recordset(payload->'sets') as x(id uuid) where x.id is null
  ) then
    raise exception 'Every set must have an id';
  end if;

  -- exercise must be a master exercise or the caller's own (exercises RLS hides others)
  if exists (
    select 1
    from jsonb_to_recordset(payload->'sets') as x(exercise_id uuid)
    where not exists (select 1 from public.exercises e where e.id = x.exercise_id)
  ) then
    raise exception 'Invalid exercise_id in payload';
  end if;

  -- upsert header; a workout owned by someone else never matches the WHERE
  insert into public.workouts (id, user_id, date, notes)
  values (
    coalesce((payload->>'id')::uuid, gen_random_uuid()),
    v_user_id,
    coalesce((payload->>'date')::timestamptz, now()),
    payload->>'notes'
  )
  on conflict (id) do update
    set date  = coalesce((payload->>'date')::timestamptz, public.workouts.date),
        notes = excluded.notes
    where public.workouts.user_id = v_user_id
  returning id into v_workout_id;

  if v_workout_id is null then
    raise exception 'Workout not found or not owned by user';
  end if;

  -- upsert sets by id so created_at is preserved on edit
  insert into public.sets (id, workout_id, user_id, exercise_id, exercise_order,
                           set_number, set_type, reps, weight_kg, rpe)
  select x.id, v_workout_id, v_user_id, x.exercise_id, coalesce(x.exercise_order, 1),
         x.set_number, coalesce(x.set_type, 'working'), x.reps, x.weight_kg, x.rpe
  from jsonb_to_recordset(payload->'sets') as x(
    id uuid, exercise_id uuid, exercise_order int, set_number int,
    set_type text, reps int, weight_kg numeric, rpe numeric
  )
  on conflict (id) do update
    set exercise_id    = excluded.exercise_id,
        exercise_order = excluded.exercise_order,
        set_number     = excluded.set_number,
        set_type       = excluded.set_type,
        reps           = excluded.reps,
        weight_kg      = excluded.weight_kg,
        rpe            = excluded.rpe
    where public.sets.workout_id = v_workout_id and public.sets.user_id = v_user_id;

  -- remove sets that are no longer in the payload
  delete from public.sets s
  where s.workout_id = v_workout_id
    and s.user_id = v_user_id
    and not exists (
      select 1 from jsonb_to_recordset(payload->'sets') as x(id uuid) where x.id = s.id
    );

  return v_workout_id;
end;
$$;

revoke execute on function public.save_workout(jsonb) from public, anon;
grant execute on function public.save_workout(jsonb) to authenticated;

-- Sets from the most recent earlier workout that contained this exercise (for auto-fill)
create or replace function public.get_previous_sets(p_exercise_id uuid, p_before timestamptz default now())
returns table (set_number int, set_type text, reps int, weight_kg numeric, rpe numeric, workout_date timestamptz)
language sql
stable
security invoker
set search_path = ''
as $$
  with last_workout as (
    select w.id, w.date
    from public.workouts w
    join public.sets s on s.workout_id = w.id
    where s.exercise_id = p_exercise_id and w.date < p_before
    order by w.date desc
    limit 1
  )
  select s.set_number, s.set_type, s.reps, s.weight_kg, s.rpe, lw.date
  from last_workout lw
  join public.sets s on s.workout_id = lw.id and s.exercise_id = p_exercise_id
  order by s.set_number;
$$;

revoke execute on function public.get_previous_sets(uuid, timestamptz) from public, anon;
grant execute on function public.get_previous_sets(uuid, timestamptz) to authenticated;
