-- 0005_master_exercises.sql
-- Idempotent master exercise seed (~40 standard lifts, 6 categories)
-- Uses ON CONFLICT DO NOTHING on lower(name) where user_id IS NULL

INSERT INTO public.exercises (name, category, user_id)
VALUES
  -- Chest (7)
  ('Bench Press', 'Chest', NULL),
  ('Incline Bench Press', 'Chest', NULL),
  ('Decline Bench Press', 'Chest', NULL),
  ('Dumbbell Fly', 'Chest', NULL),
  ('Cable Crossover', 'Chest', NULL),
  ('Chest Dip', 'Chest', NULL),
  ('Push-Up', 'Chest', NULL),
  -- Back (7)
  ('Deadlift', 'Back', NULL),
  ('Barbell Row', 'Back', NULL),
  ('Pull-Up', 'Back', NULL),
  ('Lat Pulldown', 'Back', NULL),
  ('Seated Cable Row', 'Back', NULL),
  ('T-Bar Row', 'Back', NULL),
  ('Face Pull', 'Back', NULL),
  -- Shoulders (7)
  ('Overhead Press', 'Shoulders', NULL),
  ('Dumbbell Lateral Raise', 'Shoulders', NULL),
  ('Front Raise', 'Shoulders', NULL),
  ('Arnold Press', 'Shoulders', NULL),
  ('Reverse Fly', 'Shoulders', NULL),
  ('Upright Row', 'Shoulders', NULL),
  ('Shrug', 'Shoulders', NULL),
  -- Legs (8)
  ('Squat', 'Legs', NULL),
  ('Front Squat', 'Legs', NULL),
  ('Leg Press', 'Legs', NULL),
  ('Romanian Deadlift', 'Legs', NULL),
  ('Leg Curl', 'Legs', NULL),
  ('Leg Extension', 'Legs', NULL),
  ('Bulgarian Split Squat', 'Legs', NULL),
  ('Calf Raise', 'Legs', NULL),
  -- Arms (7)
  ('Barbell Curl', 'Arms', NULL),
  ('Dumbbell Curl', 'Arms', NULL),
  ('Hammer Curl', 'Arms', NULL),
  ('Tricep Pushdown', 'Arms', NULL),
  ('Skull Crusher', 'Arms', NULL),
  ('Overhead Tricep Extension', 'Arms', NULL),
  ('Preacher Curl', 'Arms', NULL),
  -- Core (5)
  ('Plank', 'Core', NULL),
  ('Hanging Leg Raise', 'Core', NULL),
  ('Cable Crunch', 'Core', NULL),
  ('Ab Wheel Rollout', 'Core', NULL),
  ('Russian Twist', 'Core', NULL)
ON CONFLICT (lower(name)) WHERE user_id IS NULL DO NOTHING;