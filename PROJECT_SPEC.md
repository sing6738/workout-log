# Workout Log — Project Spec (for Claude Code)

A full-stack weight-training log built as a portfolio piece for Full-stack / Frontend Developer applications.
Priorities: correctness, security (RLS), tested logic, clear README. A small, polished, deployed app beats a large half-finished one.

---

## 0. Working rules for Claude Code

- Work **one step at a time** (see Roadmap). Finish a step, run checks, summarize, then stop and wait.
- Before finishing any step run: `npm run typecheck`, `npm run lint`, `npm run test`. Report failures honestly; do not skip or weaken tests.
- All DB changes go through files in `supabase/migrations/` (never via the dashboard). After schema changes regenerate types: `supabase gen types typescript --local > src/types/database.ts`.
- Never put secrets in client code. Only `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` may be exposed to the browser. Strava `client_secret`, service-role key and Strava tokens live only in Edge Function secrets / server-side tables.
- Every table has RLS enabled. Every new table/view/function must state who can access it.
- Development machine is Windows: use cross-platform npm scripts (no bash-only scripts), and note any command that needs Docker Desktop / WSL2 (needed for local Supabase).
- If something in this spec looks wrong or conflicts with current library/API docs, say so and propose a change instead of silently deviating. Verify Supabase and Strava details against their current docs.
- Commit in small, conventional-commit-style commits.

## 1. Scope

**In scope**
- Weight training log: workouts → exercises → sets (reps, weight, RPE, set type).
- Analytics: progressive overload chart per exercise, volume, estimated 1RM, automatic PR detection.
- Cardio: **not entered manually**. Imported via `.gpx` / `.csv` upload (main demo path) and Strava API (optional, OAuth 2.0).
- CSV export/import of workouts.
- Cross-device sync via Supabase Auth.

**Out of scope**: manual cardio/sleep entry, social features, payments, native apps.

## 2. Tech stack

| Area | Choice |
|---|---|
| Frontend | React + Vite + **TypeScript**, Tailwind CSS, React Router |
| Server state | TanStack Query (later: persisted cache for offline queue) |
| Validation | Zod (form input, CSV/GPX parsing, RPC payloads) |
| Charts | Recharts (with accessible table alternative) |
| Backend | Supabase: Postgres, Auth, RLS, Edge Functions (Strava only) |
| Maps (Step 3) | Leaflet + decoded polyline / GPX track |
| Tests | Vitest (logic), Playwright (e2e), pgTAP (RLS / DB functions) |
| CI/CD | GitHub Actions (typecheck, lint, test), Vercel (preview per PR + production) |

## 3. Repo structure

```
/
├─ CLAUDE.md                  # short; contains: @PROJECT_SPEC.md
├─ PROJECT_SPEC.md
├─ README.md                  # case study (see §9)
├─ supabase/
│  ├─ config.toml
│  ├─ migrations/
│  │  ├─ 0001_schema.sql
│  │  ├─ 0002_rls.sql
│  │  ├─ 0003_functions.sql
│  │  ├─ 0004_views.sql
│  │  ├─ 0005_master_exercises.sql
│  │  └─ 0006_strava.sql      # Step 3
│  ├─ functions/              # Step 3
│  │  ├─ strava-connect/
│  │  ├─ strava-exchange/
│  │  └─ strava-sync/
│  ├─ tests/                  # pgTAP
│  └─ seed.sql                # master exercises (+ demo data helper)
├─ src/
│  ├─ app/                    # router, providers, layout
│  ├─ features/
│  │  ├─ auth/  workouts/  exercises/  analytics/  cardio/  settings/
│  ├─ lib/                    # supabase.ts, e1rm.ts, units.ts, plates.ts, gpx.ts, csv.ts
│  ├─ components/ui/
│  └─ types/database.ts       # generated, do not edit
├─ e2e/                       # Playwright
└─ .github/workflows/ci.yml
```

Keep pure logic (e1RM, unit conversion, plate calculator, GPX/Haversine, CSV mapping) in `src/lib/` with Vitest tests. Keep components thin.

## 4. Database

Design decisions:
- `profiles` mirrors `auth.users`; a trigger creates it on signup (otherwise every FK to `profiles` fails for new users).
- `exercises.user_id IS NULL` = system master exercise; otherwise a user's custom exercise.
- `sets.user_id` is denormalized so RLS is a simple column check. A **composite FK** `(workout_id, user_id) → workouts(id, user_id)` makes the DB guarantee a set belongs to a workout of the same owner.
- Exercise order inside a workout is `sets.exercise_order` (kept simple; a `workout_exercises` table is a possible later refactor).
- Weights stored in kg; `profiles.weight_unit` only affects display (round to sensible plate increments when showing lbs).
- Client generates UUIDs for sets/workouts so retries and offline queueing are idempotent.
- "Previous set" and chart ordering use `workouts.date`, **not** `sets.created_at`.
- PRs are computed from views (window functions), not stored in a table, so edits/deletes can never leave stale PRs.
- The migrations below have not been executed yet: run them locally, fix any errors, and cover them with pgTAP tests.

### 4.1 `0001_schema.sql`

```sql
create table public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text,
  weight_unit text not null default 'kg' check (weight_unit in ('kg', 'lbs')),
  timezone text not null default 'Asia/Bangkok',
  created_at timestamptz not null default now()
);

create table public.exercises (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles(id) on delete cascade, -- NULL = system master
  name text not null,
  category text not null,
  created_at timestamptz not null default now()
);
create unique index exercises_master_name_idx on public.exercises (lower(name)) where user_id is null;
create unique index exercises_custom_name_idx on public.exercises (user_id, lower(name)) where user_id is not null;
create index exercises_user_idx on public.exercises (user_id);

create table public.workouts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  date timestamptz not null default now(),
  notes text,
  created_at timestamptz not null default now(),
  constraint workouts_id_user_uk unique (id, user_id)
);
create index workouts_user_date_idx on public.workouts (user_id, date desc);

create table public.sets (
  id uuid primary key default gen_random_uuid(), -- client may supply
  workout_id uuid not null,
  user_id uuid not null references public.profiles(id) on delete cascade,
  exercise_id uuid not null references public.exercises(id) on delete no action,
  exercise_order int not null default 1 check (exercise_order > 0),
  set_number int not null check (set_number > 0),
  set_type text not null default 'working'
    check (set_type in ('warmup', 'working', 'dropset', 'failure')),
  reps int not null check (reps > 0),
  weight_kg numeric(6,2) not null check (weight_kg >= 0),
  rpe numeric(3,1) check (rpe between 1 and 10),
  created_at timestamptz not null default now(),
  constraint sets_workout_owner_fk foreign key (workout_id, user_id)
    references public.workouts (id, user_id) on delete cascade
);
create index sets_user_exercise_idx on public.sets (user_id, exercise_id, workout_id);
create index sets_workout_idx on public.sets (workout_id);
create index sets_exercise_idx on public.sets (exercise_id);

create table public.cardio_logs (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  source_type text not null check (source_type in ('gpx', 'csv', 'strava')),
  external_id text not null,          -- Strava activity id, or SHA-256 of the uploaded file
  distance_km numeric(6,2) not null check (distance_km >= 0),
  duration_seconds int not null check (duration_seconds > 0),
  summary_polyline text,
  avg_heart_rate int,
  elevation_gain_m numeric(6,2),
  start_time timestamptz not null,
  created_at timestamptz not null default now(),
  constraint cardio_unique_external unique (user_id, source_type, external_id)
);
create index cardio_user_start_idx on public.cardio_logs (user_id, start_time desc);
```

### 4.2 `0002_rls.sql`

```sql
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
```

### 4.3 `0003_functions.sql`

```sql
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
```

### 4.4 `0004_views.sql`

```sql
-- All views MUST be security_invoker so RLS of the underlying tables applies.

create or replace view public.view_exercise_stats
with (security_invoker = true) as
select
  s.id           as set_id,
  s.workout_id,
  s.user_id,
  s.exercise_id,
  s.set_number,
  s.set_type,
  s.reps,
  s.weight_kg,
  s.rpe,
  w.date         as workout_date,
  (w.date at time zone p.timezone)::date as workout_day,
  -- Epley; unreliable above ~12 reps, so NULL there
  case
    when s.reps = 1  then s.weight_kg
    when s.reps <= 12 then round(s.weight_kg * (1.0 + s.reps::numeric / 30.0), 2)
    else null
  end as estimated_1rm,
  round(s.weight_kg * s.reps, 2) as volume
from public.sets s
join public.workouts w on w.id = s.workout_id
join public.profiles p on p.id = w.user_id
where s.set_type <> 'warmup';

-- One row per exercise per day: the data behind the progressive-overload chart
create or replace view public.view_daily_exercise_summary
with (security_invoker = true) as
select
  user_id, exercise_id, workout_day,
  sum(volume)         as total_volume,
  max(weight_kg)      as top_weight,
  max(estimated_1rm)  as best_e1rm,
  count(*)            as working_sets
from public.view_exercise_stats
group by user_id, exercise_id, workout_day;

-- Flags each set that beat everything the user did earlier for that exercise
create or replace view public.view_set_prs
with (security_invoker = true) as
select
  v.*,
  v.weight_kg > coalesce(max(v.weight_kg) over w, 0) as is_weight_pr,
  (v.estimated_1rm is not null
     and v.estimated_1rm > coalesce(max(v.estimated_1rm) over w, 0)) as is_e1rm_pr
from public.view_exercise_stats v
window w as (
  partition by v.user_id, v.exercise_id
  order by v.workout_date, v.workout_id, v.set_number, v.set_id
  rows between unbounded preceding and 1 preceding
);
```

### 4.5 `0006_strava.sql` (Step 3)

- `strava_oauth_states (state text primary key, user_id uuid not null, expires_at timestamptz not null, used boolean default false)`
- `strava_connections (user_id uuid primary key references profiles on delete cascade, athlete_id bigint, access_token text, refresh_token text, expires_at timestamptz, scope text, updated_at timestamptz)`
- Both tables: RLS **enabled with no policies** for `anon`/`authenticated` (service role only). Prefer Supabase Vault for token encryption if practical.

### 4.6 pgTAP tests (`supabase/tests/`)

- User A cannot select/insert/update/delete User B's workouts, sets, cardio, custom exercises, profile.
- Master exercises readable by any authenticated user, not writable.
- `save_workout`: creates; edits (set `created_at` preserved); removes dropped sets; rejects another user's workout id; rejects another user's custom exercise id; rejects sets without id.
- Deleting an account (cascade from `auth.users`) succeeds and leaves no rows.
- `view_set_prs`: first set is a PR; equal weight is not; warm-ups ignored; editing/deleting a set changes PR flags accordingly.
- Views respect RLS (a user only sees their own rows).

## 5. Frontend behavior

**Routes**: `/login`, `/workouts`, `/workouts/new`, `/workouts/:id`, `/exercises`, `/analytics/:exerciseId`, `/cardio`, `/settings`.

**Workout editor (core UX, mobile-first)**
- Add exercise → rows of sets (weight, reps, RPE in 0.5 steps, set type toggle for warm-up).
- On adding an exercise, call `get_previous_sets` and show previous weight/reps as placeholders; a "copy last set" button.
- Numeric inputs use `inputMode="decimal"`; large +/- steppers.
- Save via `rpc('save_workout')` with client-generated UUIDs; validate with Zod before sending.
- Show loading, empty, and error states everywhere.

**Analytics**: per-exercise chart of top weight / e1RM / volume over time (from `view_daily_exercise_summary`), PR markers (from `view_set_prs`), date-range filter. Chart data must never be aggregated client-side from raw sets. Provide a table alternative and keyboard-accessible controls.

**Cardio (Step 3)**: `.gpx` and `.csv` upload parsed client-side (Haversine distance, duration, elevation gain; file SHA-256 as `external_id` so re-import is a no-op). Route map with Leaflet, pace chart. Strava import optional.

**Units**: store kg; display per `profiles.weight_unit`; round lbs to 0.5/1 lb.

**Timezone**: group by `workout_day` (per user's `profiles.timezone`), never by UTC date.

## 6. Strava integration (Step 3, optional path)

Principle: `client_secret` and tokens never reach the browser. Strava is a **linked account**, separate from Supabase login (do not rely on Supabase's Strava auth provider for data access).

1. React calls Edge Function `strava-connect` with the Supabase JWT → function stores a random one-time `state` (with TTL and `user_id`) and returns the Strava authorize URL.
2. User approves on Strava → redirected to `/integrations/strava/callback?code&state`.
3. React sends `code` + `state` to `strava-exchange` (with JWT) → function validates JWT and `state`, exchanges the code using `client_secret` from function secrets, stores tokens in `strava_connections`.
4. `strava-sync` (button, later cron) refreshes the token when expired (always persist the newest refresh token), fetches activities, **upserts** into `cardio_logs` on `(user_id, source_type, external_id)`.
5. React only reads `cardio_logs` through normal RLS.

Scope: `activity:read` (use `activity:read_all` only if private activities are needed). Verify current Strava rules before building: as far as I know a newly created Strava app can connect only its owner until approved for more athletes, and there are per-app rate limits. Therefore GPX/CSV import is the main demo path and Strava is shown in the README with a GIF/video. Webhooks are a stretch goal.

## 7. Roadmap and acceptance criteria

**Step 0 — Foundation.** Vite + TS + Tailwind, ESLint/Prettier, Supabase local setup, migrations 0001–0005 (including master exercises), generated types, Vercel deploy with previews, GitHub Actions CI. *Done when:* `supabase db reset` works locally, CI is green, an empty app is live on Vercel.

**Step 1 — Core CRUD + Auth.** Email/password auth (session persistence, protected routes), profile, exercises (master + custom), workout list/editor via `save_workout`, previous-set auto-fill, copy-last-set. *Done when:* a new user can sign up, log a workout, edit it, delete it, and see it on another device; pgTAP RLS tests pass.

**Step 2 — Analytics & PR.** Progressive-overload chart, volume, e1RM, PR badges (from views), unit setting, timezone-correct grouping. Vitest for `e1rm.ts` / `units.ts`. *Done when:* charts match hand-computed values on seed data.

**Step 3 — Import/Export and Cardio.** CSV export/import for workouts, GPX/CSV cardio import with dedupe, route map + pace chart, then Strava OAuth (last, optional; migration `0006_strava.sql`). *Done when:* re-importing the same file creates no duplicates.

**Step 4 — Polish.** Timestamp-based rest timer (correct when tab is backgrounded; vibration/notification), plate calculator, workout templates / "start from last workout", consistency heatmap calendar, dark mode, PWA + optimistic updates + offline queue (idempotent thanks to client UUIDs).

**Step 5 — Demo, tests, README.** One-click demo (see below), Playwright e2e (login → log workout → see chart), Lighthouse/accessibility pass, README case study.

**Demo mode (recommendation, verify against current Supabase docs):** use anonymous sign-in (`supabase.auth.signInAnonymously()`, enable captcha) plus a `seed_demo_data()` RPC that creates ~3 months of realistic workouts for that user; clean up old anonymous users with pg_cron. Each visitor gets a private sandbox and no shared credentials.

## 8. Testing checklist

- Vitest: e1RM (Epley, 1-rep case, >12 reps), unit conversion/rounding, plate calculator, GPX distance/elevation, CSV mapping + Zod errors.
- pgTAP: see §4.6.
- Playwright: signup/login, create + edit workout, previous-value auto-fill, chart renders, cross-user isolation smoke test.

## 9. README (portfolio case study) must include

Live demo link + demo-mode instructions; GIF of the logging flow; ERD; architecture diagram of the Strava flow; "Design decisions & trade-offs" (RLS + composite FK, views vs stored PRs, atomic RPC, client UUIDs/idempotency, why Strava is optional); testing/CI badges; how to run locally; known limitations.

## 10. First prompt to give Claude Code

> Read PROJECT_SPEC.md. Implement **Step 0 only**. Create the repo scaffolding, run the migrations 0001–0004 locally, fix any SQL errors you find (and tell me what you changed), add the master-exercise seed, generate types, and set up CI. Do not start Step 1. When done, summarize what you did, what you verified, and anything in the spec you disagree with.
