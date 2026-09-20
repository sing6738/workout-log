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
