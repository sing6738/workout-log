alter table public.profiles enable row level security;
alter table public.exercises enable row level security;
alter table public.workouts enable row level security;
alter table public.sets enable row level security;
alter table public.cardio_logs enable row level security;

-- (select auth.uid()) lets the planner evaluate it once per statement.

create policy "own profile select" on public.profiles for select to authenticated
  using (id = (select auth.uid()));
create policy "own profile update" on public.profiles for update to authenticated
  using (id = (select auth.uid())) with check (id = (select auth.uid()));
-- no insert policy: rows are created by the handle_new_user trigger (security definer)

create policy "read master or own exercises" on public.exercises for select to authenticated
  using (user_id is null or user_id = (select auth.uid()));
create policy "manage own exercises" on public.exercises for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "manage own workouts" on public.workouts for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "manage own sets" on public.sets for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));

create policy "manage own cardio" on public.cardio_logs for all to authenticated
  using (user_id = (select auth.uid())) with check (user_id = (select auth.uid()));
