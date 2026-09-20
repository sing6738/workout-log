-- supabase/tests/database/rls_views.test.sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(18);  -- 5 tables exist + 5 RLS enabled + 1 trigger def + 1 trigger execution + 3 views security_invoker + 3 master exercise checks

-- Tables exist & RLS enabled on all 5 public tables
SELECT has_table('public', 'profiles', 'profiles table exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.profiles'::regclass), 'RLS enabled on profiles');

SELECT has_table('public', 'exercises', 'exercises table exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.exercises'::regclass), 'RLS enabled on exercises');

SELECT has_table('public', 'workouts', 'workouts table exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.workouts'::regclass), 'RLS enabled on workouts');

SELECT has_table('public', 'sets', 'sets table exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.sets'::regclass), 'RLS enabled on sets');

SELECT has_table('public', 'cardio_logs', 'cardio_logs table exists');
SELECT ok((SELECT relrowsecurity FROM pg_class WHERE oid = 'public.cardio_logs'::regclass), 'RLS enabled on cardio_logs');

-- Trigger definition on auth.users
SELECT trigger_is('auth', 'users', 'on_auth_user_created', 'public', 'handle_new_user');

-- Trigger execution: insert into auth.users creates matching row in public.profiles
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES (
  '11111111-1111-1111-1111-111111111111'::uuid,
  'testuser@example.com',
  '{"name": "Test User"}'::jsonb
);

SELECT results_eq(
  $$SELECT display_name FROM public.profiles WHERE id = '11111111-1111-1111-1111-111111111111'$$,
  $$VALUES ('Test User')$$,
  'insert into auth.users creates matching profile'
);

-- All public views: security_invoker = true
SELECT ok((SELECT coalesce(reloptions::text, '') LIKE '%security_invoker=true%' FROM pg_class WHERE oid = 'public.view_exercise_stats'::regclass), 'view_exercise_stats is security_invoker');
SELECT ok((SELECT coalesce(reloptions::text, '') LIKE '%security_invoker=true%' FROM pg_class WHERE oid = 'public.view_daily_exercise_summary'::regclass), 'view_daily_exercise_summary is security_invoker');
SELECT ok((SELECT coalesce(reloptions::text, '') LIKE '%security_invoker=true%' FROM pg_class WHERE oid = 'public.view_set_prs'::regclass), 'view_set_prs is security_invoker');

-- Master exercises exist (user_id IS NULL = master)
SELECT ok(
  (SELECT count(*) FROM public.exercises WHERE user_id IS NULL) >= 30,
  'at least 30 master exercises seeded'
);

-- Master exercise categories are in the allowed set
SELECT is_empty(
  $$SELECT DISTINCT category FROM public.exercises
    WHERE user_id IS NULL
      AND category NOT IN ('Chest', 'Back', 'Shoulders', 'Legs', 'Arms', 'Core')$$,
  'all master exercise categories are in {Chest, Back, Shoulders, Legs, Arms, Core}'
);

-- No case-insensitive duplicate master exercises
SELECT is_empty(
  $$SELECT lower(name), count(*)
    FROM public.exercises WHERE user_id IS NULL
    GROUP BY lower(name) HAVING count(*) > 1$$,
  'no case-insensitive duplicate master exercises'
);

SELECT * FROM finish();
ROLLBACK;