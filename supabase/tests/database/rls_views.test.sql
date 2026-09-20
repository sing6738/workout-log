-- supabase/tests/database/rls_views.test.sql
BEGIN;
CREATE EXTENSION IF NOT EXISTS pgtap;

SELECT plan(46);

-- ============================================================================
-- 1. Schema & RLS Enabled on Public Tables (10 tests)
-- ============================================================================
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

-- ============================================================================
-- 2. Trigger Definition & Views Configuration (4 tests)
-- ============================================================================
SELECT trigger_is('auth', 'users', 'on_auth_user_created', 'public', 'handle_new_user', 'trigger on_auth_user_created exists on auth.users');

SELECT ok((SELECT coalesce(reloptions::text, '') LIKE '%security_invoker=true%' FROM pg_class WHERE oid = 'public.view_exercise_stats'::regclass), 'view_exercise_stats is security_invoker');
SELECT ok((SELECT coalesce(reloptions::text, '') LIKE '%security_invoker=true%' FROM pg_class WHERE oid = 'public.view_daily_exercise_summary'::regclass), 'view_daily_exercise_summary is security_invoker');
SELECT ok((SELECT coalesce(reloptions::text, '') LIKE '%security_invoker=true%' FROM pg_class WHERE oid = 'public.view_set_prs'::regclass), 'view_set_prs is security_invoker');

-- ============================================================================
-- 3. Master Exercises Seed Verification (3 tests)
-- ============================================================================
SELECT ok(
  (SELECT count(*) FROM public.exercises WHERE user_id IS NULL) >= 30,
  'at least 30 master exercises seeded'
);

SELECT is_empty(
  $$SELECT DISTINCT category FROM public.exercises
    WHERE user_id IS NULL
      AND category NOT IN ('Chest', 'Back', 'Shoulders', 'Legs', 'Arms', 'Core')$$,
  'all master exercise categories are in {Chest, Back, Shoulders, Legs, Arms, Core}'
);

SELECT is_empty(
  $$SELECT lower(name), count(*)
    FROM public.exercises WHERE user_id IS NULL
    GROUP BY lower(name) HAVING count(*) > 1$$,
  'no case-insensitive duplicate master exercises'
);

-- ============================================================================
-- 4. User Signup & Timezone Validation in handle_new_user (4 tests)
-- ============================================================================
-- Setup Test Users in auth.users
INSERT INTO auth.users (id, email, raw_user_meta_data)
VALUES
  ('11111111-1111-1111-1111-111111111111'::uuid, 'usera@example.com', '{"name": "User A", "timezone": "America/New_York"}'::jsonb),
  ('22222222-2222-2222-2222-222222222222'::uuid, 'userb@example.com', '{"name": "User B", "timezone": "Europe/London"}'::jsonb),
  ('33333333-3333-3333-3333-333333333333'::uuid, 'usertzinv@example.com', '{"name": "User Bad TZ", "timezone": "Invalid/Timezone"}'::jsonb),
  ('44444444-4444-4444-4444-444444444444'::uuid, 'usertznull@example.com', '{"name": "User Null TZ"}'::jsonb);

-- Setup dedicated custom exercises for User A and User B
INSERT INTO public.exercises (id, user_id, name, category)
VALUES
  ('e1111111-1111-1111-1111-111111111111'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'User A Custom Squat', 'Legs'),
  ('e2222222-2222-2222-2222-222222222222'::uuid, '22222222-2222-2222-2222-222222222222'::uuid, 'User B Custom Press', 'Shoulders');

SELECT results_eq(
  $$SELECT display_name, timezone FROM public.profiles WHERE id = '11111111-1111-1111-1111-111111111111'::uuid$$,
  $$VALUES ('User A'::text, 'America/New_York'::text)$$,
  'handle_new_user sets display_name and valid timezone America/New_York'
);

SELECT results_eq(
  $$SELECT timezone FROM public.profiles WHERE id = '22222222-2222-2222-2222-222222222222'::uuid$$,
  $$VALUES ('Europe/London'::text)$$,
  'handle_new_user sets valid timezone Europe/London'
);

SELECT results_eq(
  $$SELECT timezone FROM public.profiles WHERE id = '33333333-3333-3333-3333-333333333333'::uuid$$,
  $$VALUES ('Asia/Bangkok'::text)$$,
  'handle_new_user falls back to column default Asia/Bangkok when timezone is invalid'
);

SELECT results_eq(
  $$SELECT timezone FROM public.profiles WHERE id = '44444444-4444-4444-4444-444444444444'::uuid$$,
  $$VALUES ('Asia/Bangkok'::text)$$,
  'handle_new_user falls back to column default Asia/Bangkok when timezone is null'
);

-- ============================================================================
-- 5. Exercises RLS: Master vs Custom Exercises (4 tests)
-- ============================================================================
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

-- User A can read master exercises
SELECT ok(
  (SELECT count(*) FROM public.exercises WHERE user_id IS NULL) >= 30,
  'User A can read master exercises'
);

-- User A cannot insert master exercise (user_id IS NULL)
SELECT throws_ok(
  $$INSERT INTO public.exercises (name, category) VALUES ('Hacked Master Exercise', 'Chest')$$,
  '42501',
  NULL,
  'Authenticated users cannot create master exercises (user_id IS NULL)'
);

-- User A can create custom exercise
SELECT lives_ok(
  $$INSERT INTO public.exercises (id, user_id, name, category)
    VALUES ('aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid, '11111111-1111-1111-1111-111111111111'::uuid, 'User A Custom Curl', 'Arms')$$,
  'User A can create custom exercise'
);

-- User B cannot see User A custom exercise
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

SELECT is_empty(
  $$SELECT * FROM public.exercises WHERE id = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'::uuid$$,
  'User B cannot select User A custom exercise'
);

-- ============================================================================
-- 6. Atomic save_workout, RLS & Cross-User Security (12 tests)
-- ============================================================================
-- User A creates workout and sets via save_workout using their custom exercise
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

SELECT lives_ok(
  $$
    SELECT public.save_workout(jsonb_build_object(
      'id', 'a1111111-1111-1111-1111-111111111111'::uuid,
      'date', '2026-09-20T10:00:00Z'::timestamptz,
      'notes', 'User A Leg Day',
      'sets', jsonb_build_array(
        jsonb_build_object(
          'id', 'b1111111-1111-1111-1111-111111111111'::uuid,
          'exercise_id', 'e1111111-1111-1111-1111-111111111111'::uuid,
          'exercise_order', 1,
          'set_number', 1,
          'set_type', 'warmup',
          'reps', 10,
          'weight_kg', 60.0,
          'rpe', 6.0
        ),
        jsonb_build_object(
          'id', 'b1111111-1111-1111-1111-111111111112'::uuid,
          'exercise_id', 'e1111111-1111-1111-1111-111111111111'::uuid,
          'exercise_order', 1,
          'set_number', 2,
          'set_type', 'working',
          'reps', 5,
          'weight_kg', 100.0,
          'rpe', 8.0
        ),
        jsonb_build_object(
          'id', 'b1111111-1111-1111-1111-111111111113'::uuid,
          'exercise_id', 'e1111111-1111-1111-1111-111111111111'::uuid,
          'exercise_order', 1,
          'set_number', 3,
          'set_type', 'working',
          'reps', 5,
          'weight_kg', 100.0,
          'rpe', 8.5
        )
      )
    ))
  $$,
  'User A can create workout with warmup and working sets via save_workout'
);

-- User B isolation: cannot select User A workout or sets
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

SELECT is_empty(
  $$SELECT * FROM public.workouts WHERE id = 'a1111111-1111-1111-1111-111111111111'::uuid$$,
  'User B cannot select User A workout'
);

SELECT is_empty(
  $$SELECT * FROM public.sets WHERE workout_id = 'a1111111-1111-1111-1111-111111111111'::uuid$$,
  'User B cannot select User A sets'
);

-- Composite-FK Cross-User test: User B inserting a set referencing User A workout fails with 23503
SELECT throws_ok(
  $$
    INSERT INTO public.sets (
      id, workout_id, user_id, exercise_id, exercise_order, set_number, set_type, reps, weight_kg
    ) VALUES (
      'b2222222-2222-2222-2222-222222222221'::uuid,
      'a1111111-1111-1111-1111-111111111111'::uuid,
      '22222222-2222-2222-2222-222222222222'::uuid,
      'e2222222-2222-2222-2222-222222222222'::uuid,
      1, 1, 'working', 10, 50.0
    )
  $$,
  '23503',
  NULL,
  'User B cannot insert set referencing User A workout due to composite FK (workout_id, user_id)'
);

-- save_workout cross-user rejection: User B cannot modify User A workout
SELECT throws_ok(
  $$
    SELECT public.save_workout(jsonb_build_object(
      'id', 'a1111111-1111-1111-1111-111111111111'::uuid,
      'date', now(),
      'notes', 'Hacked by User B',
      'sets', jsonb_build_array(
        jsonb_build_object(
          'id', 'b2222222-2222-2222-2222-222222222222'::uuid,
          'exercise_id', 'e2222222-2222-2222-2222-222222222222'::uuid,
          'exercise_order', 1,
          'set_number', 1,
          'set_type', 'working',
          'reps', 10,
          'weight_kg', 100.0
        )
      )
    ))
  $$,
  NULL,
  NULL,
  'save_workout rejects modifying another user workout id'
);

-- Verify as postgres role that User A workout was not modified by User B rejected update
SET LOCAL ROLE postgres;
SELECT results_eq(
  $$SELECT user_id, notes FROM public.workouts WHERE id = 'a1111111-1111-1111-1111-111111111111'::uuid$$,
  $$VALUES ('11111111-1111-1111-1111-111111111111'::uuid, 'User A Leg Day'::text)$$,
  'User A workout row remains untouched after User B rejected update'
);

-- save_workout cross-user exercise rejection: User A cannot use User B custom exercise
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

SELECT throws_ok(
  $$
    SELECT public.save_workout(jsonb_build_object(
      'id', gen_random_uuid(),
      'date', now(),
      'sets', jsonb_build_array(
        jsonb_build_object(
          'id', gen_random_uuid(),
          'exercise_id', 'e2222222-2222-2222-2222-222222222222'::uuid,
          'exercise_order', 1,
          'set_number', 1,
          'set_type', 'working',
          'reps', 10,
          'weight_kg', 40.0
        )
      )
    ))
  $$,
  'P0001',
  'Invalid exercise_id in payload',
  'save_workout rejects another user custom exercise id'
);

-- save_workout validation: rejects set without id
SELECT throws_ok(
  $$
    SELECT public.save_workout(jsonb_build_object(
      'id', gen_random_uuid(),
      'date', now(),
      'sets', jsonb_build_array(
        jsonb_build_object(
          'exercise_id', 'e1111111-1111-1111-1111-111111111111'::uuid,
          'exercise_order', 1,
          'set_number', 1,
          'set_type', 'working',
          'reps', 10,
          'weight_kg', 50.0
        )
      )
    ))
  $$,
  'P0001',
  'Every set must have an id',
  'save_workout rejects sets without client-generated id'
);

-- save_workout unauthenticated check
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

SELECT throws_ok(
  $$
    SELECT public.save_workout(jsonb_build_object(
      'date', now(),
      'sets', jsonb_build_array()
    ))
  $$,
  '28000',
  'Not authenticated',
  'save_workout rejects unauthenticated call with 28000'
);

-- User A updates workout: edits set 2 weight, removes set 3, adds set 4
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "11111111-1111-1111-1111-111111111111", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '11111111-1111-1111-1111-111111111111', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

SELECT lives_ok(
  $$
    SELECT public.save_workout(jsonb_build_object(
      'id', 'a1111111-1111-1111-1111-111111111111'::uuid,
      'date', '2026-09-20T10:00:00Z'::timestamptz,
      'notes', 'User A Leg Day (Updated)',
      'sets', jsonb_build_array(
        jsonb_build_object(
          'id', 'b1111111-1111-1111-1111-111111111111'::uuid,
          'exercise_id', 'e1111111-1111-1111-1111-111111111111'::uuid,
          'exercise_order', 1,
          'set_number', 1,
          'set_type', 'warmup',
          'reps', 10,
          'weight_kg', 60.0,
          'rpe', 6.0
        ),
        jsonb_build_object(
          'id', 'b1111111-1111-1111-1111-111111111112'::uuid,
          'exercise_id', 'e1111111-1111-1111-1111-111111111111'::uuid,
          'exercise_order', 1,
          'set_number', 2,
          'set_type', 'working',
          'reps', 5,
          'weight_kg', 110.0,
          'rpe', 9.0
        ),
        jsonb_build_object(
          'id', 'b1111111-1111-1111-1111-111111111114'::uuid,
          'exercise_id', 'e1111111-1111-1111-1111-111111111111'::uuid,
          'exercise_order', 1,
          'set_number', 3,
          'set_type', 'working',
          'reps', 3,
          'weight_kg', 120.0,
          'rpe', 9.5
        )
      )
    ))
  $$,
  'User A can update workout with edited, removed, and new sets'
);

-- Verify updated set weight
SELECT results_eq(
  $$SELECT weight_kg FROM public.sets WHERE id = 'b1111111-1111-1111-1111-111111111112'::uuid$$,
  $$VALUES (110.0::numeric)$$,
  'Updated set has new weight 110.0 kg'
);

-- Verify dropped set 3 was removed
SELECT is_empty(
  $$SELECT * FROM public.sets WHERE id = 'b1111111-1111-1111-1111-111111111113'::uuid$$,
  'Dropped set 3 was removed on save_workout update'
);

-- ============================================================================
-- 7. PR Calculation in view_set_prs & Views RLS Isolation (5 tests)
-- ============================================================================
-- Set 2 (110kg) is first working set and a PR
SELECT results_eq(
  $$SELECT is_weight_pr, is_e1rm_pr FROM public.view_set_prs WHERE set_id = 'b1111111-1111-1111-1111-111111111112'::uuid$$,
  $$VALUES (true, true)$$,
  'First working set in view_set_prs has is_weight_pr = true and is_e1rm_pr = true'
);

-- Warmup set (b1111111-1111-1111-1111-111111111111) is excluded from view_set_prs
SELECT is_empty(
  $$SELECT * FROM public.view_set_prs WHERE set_id = 'b1111111-1111-1111-1111-111111111111'::uuid$$,
  'Warmup sets are excluded from view_set_prs'
);

-- User B views isolation: sees 0 rows for User A data in all views
SET LOCAL ROLE authenticated;
SELECT set_config('request.jwt.claims', '{"sub": "22222222-2222-2222-2222-222222222222", "role": "authenticated"}', true);
SELECT set_config('request.jwt.claim.sub', '22222222-2222-2222-2222-222222222222', true);
SELECT set_config('request.jwt.claim.role', 'authenticated', true);

SELECT is_empty(
  $$SELECT * FROM public.view_exercise_stats WHERE user_id = '11111111-1111-1111-1111-111111111111'::uuid$$,
  'User B sees 0 rows in view_exercise_stats for User A'
);

SELECT is_empty(
  $$SELECT * FROM public.view_daily_exercise_summary WHERE user_id = '11111111-1111-1111-1111-111111111111'::uuid$$,
  'User B sees 0 rows in view_daily_exercise_summary for User A'
);

SELECT is_empty(
  $$SELECT * FROM public.view_set_prs WHERE user_id = '11111111-1111-1111-1111-111111111111'::uuid$$,
  'User B sees 0 rows in view_set_prs for User A'
);

-- ============================================================================
-- 8. Account Deletion Cascade (4 tests)
-- ============================================================================
SET LOCAL ROLE postgres;

DELETE FROM auth.users WHERE id = '11111111-1111-1111-1111-111111111111'::uuid;

SELECT is_empty(
  $$SELECT * FROM public.profiles WHERE id = '11111111-1111-1111-1111-111111111111'::uuid$$,
  'Cascade delete from auth.users deletes public.profiles row'
);

SELECT is_empty(
  $$SELECT * FROM public.exercises WHERE user_id = '11111111-1111-1111-1111-111111111111'::uuid$$,
  'Cascade delete from auth.users deletes custom public.exercises rows'
);

SELECT is_empty(
  $$SELECT * FROM public.workouts WHERE user_id = '11111111-1111-1111-1111-111111111111'::uuid$$,
  'Cascade delete from auth.users deletes public.workouts rows'
);

SELECT is_empty(
  $$SELECT * FROM public.sets WHERE user_id = '11111111-1111-1111-1111-111111111111'::uuid$$,
  'Cascade delete from auth.users deletes public.sets rows'
);

SELECT * FROM finish();
ROLLBACK;