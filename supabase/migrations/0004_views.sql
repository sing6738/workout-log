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
