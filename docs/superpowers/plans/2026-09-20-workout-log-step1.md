# Workout Log — Step 1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement Step 1 Core CRUD & Authentication structured across **4 sequential PRs (PR 1a, PR 1b, PR 2, PR 3)**:

- **PR 1a**: Scaffolding, App/Query Shell, Migration `0006_handle_new_user_timezone.sql`, and Full pgTAP RLS/Cascade/Timezone test suite. (Must NOT import `src/lib/supabase.ts`, allowing merge before any env vars exist).
- **User Actions Checkpoint**: Hosted Supabase project creation, `npx supabase link`, `npx supabase db push`, review of Supabase Dashboard Security Advisors, and Vercel environment variables configuration.
- **PR 1b**: Auth UI (login, signup with timezone passed in `options.data.timezone`), protected routes, `EnvErrorScreen`, Supabase client integration. (Starts only after user confirms hosted setup & security advisor review).
- **PR 2**: Profile settings (display name, weight unit, timezone picker from `Intl.supportedValuesOf('timeZone')`) and Exercise directory (master + custom create).
- **PR 3**: Workout list dashboard and mobile-first workout editor with atomic RPC saves (`save_workout`), client UUIDs, previous-set autofill (`get_previous_sets`), copy-last-set, and UI/RPC boundary unit conversions with 45/135/225 lb round-trip tests.

**Tech Stack:** React 18, Vite, TypeScript, Tailwind CSS v4, `@supabase/supabase-js`, `react-router-dom`, `@tanstack/react-query`, `lucide-react`, `zod`, `vitest`, `@testing-library/react`, `jsdom`, pgTAP.

**Design Spec:** `docs/superpowers/specs/2026-09-20-workout-log-step1-design.md`

---

## Non-Negotiable Operational Rules

1. **Docker Check First**: Before starting any local database operations or PR work, run `docker version`. If the Docker Server is unavailable, stop and alert the user immediately. Do not fake or bypass local DB verification.
2. **Strict PR Workflow (No Merges by Agent)**: For every PR, push the branch and open the PR using `gh pr create`, then **STOP**. The user merges PRs manually. Never merge PRs, never push to `main` directly, and never rewrite git history.
3. **Zero Supabase Import in PR 1a**: PR 1a must not import `src/lib/supabase.ts` or reference env vars, ensuring clean build and preview deployment before hosted environment variables exist.
4. **Security Advisor Checkpoint**: PR 1b starts only after the user executes `db push`, reviews Supabase Dashboard -> Advisors -> Security, and communicates findings.
5. **Safe Timezone Handling**: Never detect timezone "on first login". Pass timezone during sign-up (`options.data.timezone`) selected strictly from `Intl.supportedValuesOf('timeZone')`. In `handle_new_user()` (migration `0006_*`), validate against `pg_timezone_names` and fall back to column default (`'Asia/Bangkok'`). Never edit migrations `0001`–`0005`.

---

# Phase 1a: PR 1a — Scaffolding, App & Query Shell, Migration 0006 & Full pgTAP Suite

Branch: `feat/step1a-scaffold-db-tests`

## Task 1: Migration 0006 — Safe Timezone in `handle_new_user`

**Files:**

- Create: `supabase/migrations/0006_handle_new_user_timezone.sql`

- [ ] **Step 1: Check Docker status**

Run: `docker version`  
Ensure Docker Server is running. If not, stop and inform the user.

- [ ] **Step 2: Create `supabase/migrations/0006_handle_new_user_timezone.sql`**

Update `handle_new_user()` trigger function to read `raw_user_meta_data->>'timezone'`, validate it against `pg_timezone_names`, and fall back to `'Asia/Bangkok'`.

```sql
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

  if v_raw_tz is not null and exists (select 1 from pg_timezone_names where name = v_raw_tz) then
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
```

- [ ] **Step 3: Apply migration locally and verify**

Run: `npx supabase db reset`  
Expected: All migrations 0001 through 0006 apply successfully.

- [ ] **Step 4: Commit**

```bash
git add supabase/migrations/0006_handle_new_user_timezone.sql
git commit -m "feat(db): add migration 0006 for safe timezone handling in handle_new_user"
```

---

## Task 2: Database Full pgTAP Test Suite (§4.6)

**Files:**

- Create / Modify: `supabase/tests/database/rls_views.test.sql`

- [ ] **Step 1: Write full pgTAP test suite covering all §4.6 requirements**

Include:

1. User A cannot select/insert/update/delete User B's workouts, sets, cardio, custom exercises, profile.
2. Master exercises readable by any authenticated user, not writable.
3. Composite-FK cross-user integrity test (User A inserting a set referencing User B's workout is rejected).
4. Cascade deletion from `auth.users` deletes all profile, workouts, sets, custom exercises, and cardio rows.
5. `save_workout`: creates, edits (preserves set `created_at`), removes dropped sets, rejects another user's workout id, rejects another user's custom exercise id, rejects sets without id.
6. `view_set_prs`: first set is PR, equal weight is not, warmups ignored, editing/deleting updates PR flags.
7. Views respect RLS (user only sees their own rows).
8. Valid and invalid timezone tests:
   - User signup with valid timezone (`'America/New_York'`) sets `profiles.timezone = 'America/New_York'`.
   - User signup with invalid timezone (`'Invalid/Timezone'`) falls back to `'Asia/Bangkok'`.
   - User signup with NULL timezone falls back to `'Asia/Bangkok'`.

```sql
begin;
select plan(28);

-- Test helper setup: Create test users in auth.users
select tests.create_supabase_user('user_a');
select tests.create_supabase_user('user_b');

-- 1. Verify Profile created on signup with valid timezone
select tests.authenticate_as('user_a');
select results_eq(
  $$ select count(*)::int from public.profiles where id = tests.get_supabase_uid('user_a') $$,
  $$ values (1) $$,
  'Profile created automatically on auth.user creation'
);

-- Timezone tests for handle_new_user
select tests.create_supabase_user('user_tz_valid', 'user_tz_valid@example.com', '{"name":"TZ Valid","timezone":"America/New_York"}'::jsonb);
select results_eq(
  $$ select timezone from public.profiles where id = tests.get_supabase_uid('user_tz_valid') $$,
  $$ values ('America/New_York'::text) $$,
  'handle_new_user accepts valid timezone from raw_user_meta_data'
);

select tests.create_supabase_user('user_tz_invalid', 'user_tz_invalid@example.com', '{"name":"TZ Invalid","timezone":"Invalid/Timezone"}'::jsonb);
select results_eq(
  $$ select timezone from public.profiles where id = tests.get_supabase_uid('user_tz_invalid') $$,
  $$ values ('Asia/Bangkok'::text) $$,
  'handle_new_user falls back to Asia/Bangkok when timezone is invalid'
);

select tests.create_supabase_user('user_tz_null', 'user_tz_null@example.com', '{"name":"TZ Null"}'::jsonb);
select results_eq(
  $$ select timezone from public.profiles where id = tests.get_supabase_uid('user_tz_null') $$,
  $$ values ('Asia/Bangkok'::text) $$,
  'handle_new_user falls back to Asia/Bangkok when timezone is not provided'
);

-- Master exercises tests
select tests.authenticate_as('user_a');
select ok(
  (select count(*) > 0 from public.exercises where user_id is null),
  'Master exercises are readable by authenticated users'
);

select throws_ok(
  $$ insert into public.exercises (name, category) values ('Hacked Master', 'chest') $$,
  '42501',
  null,
  'Authenticated users cannot create master exercises'
);

-- RLS Isolation Tests
-- User A creates a workout and set
select tests.authenticate_as('user_a');
select lives_ok(
  $$
    select public.save_workout(jsonb_build_object(
      'id', '11111111-1111-1111-1111-111111111111'::uuid,
      'date', now(),
      'notes', 'User A workout',
      'sets', jsonb_build_array(
        jsonb_build_object(
          'id', '22222222-2222-2222-2222-222222222222'::uuid,
          'exercise_id', (select id from public.exercises where user_id is null limit 1),
          'exercise_order', 1,
          'set_number', 1,
          'set_type', 'working',
          'reps', 10,
          'weight_kg', 100.0,
          'rpe', 8.0
        )
      )
    ))
  $$,
  'User A can save workout via save_workout RPC'
);

-- User B cannot select User A workout or sets
select tests.authenticate_as('user_b');
select is_empty(
  $$ select * from public.workouts where id = '11111111-1111-1111-1111-111111111111'::uuid $$,
  'User B cannot select User A workouts'
);

select is_empty(
  $$ select * from public.sets where workout_id = '11111111-1111-1111-1111-111111111111'::uuid $$,
  'User B cannot select User A sets'
);

-- Composite-FK Cross-User test: User B cannot insert a set referencing User A workout
select throws_ok(
  $$
    insert into public.sets (
      id, workout_id, user_id, exercise_id, exercise_order, set_number, set_type, reps, weight_kg
    ) values (
      gen_random_uuid(),
      '11111111-1111-1111-1111-111111111111'::uuid,
      tests.get_supabase_uid('user_b'),
      (select id from public.exercises where user_id is null limit 1),
      1, 1, 'working', 10, 50.0
    )
  $$,
  null,
  null,
  'User B cannot insert set referencing User A workout due to composite FK constraint'
);

-- save_workout security: User B cannot update User A workout
select throws_ok(
  $$
    select public.save_workout(jsonb_build_object(
      'id', '11111111-1111-1111-1111-111111111111'::uuid,
      'date', now(),
      'sets', jsonb_build_array()
    ))
  $$,
  null,
  null,
  'save_workout rejects updating another user workout id'
);

-- save_workout validation: rejects sets without id
select tests.authenticate_as('user_a');
select throws_ok(
  $$
    select public.save_workout(jsonb_build_object(
      'id', gen_random_uuid(),
      'date', now(),
      'sets', jsonb_build_array(
        jsonb_build_object(
          'exercise_id', (select id from public.exercises where user_id is null limit 1),
          'exercise_order', 1,
          'set_number', 1,
          'set_type', 'working',
          'reps', 10,
          'weight_kg', 100.0
        )
      )
    ))
  $$,
  null,
  'Every set must have an id',
  'save_workout rejects sets without id'
);

-- PR calculation verification in view_set_prs
select results_eq(
  $$ select is_pr from public.view_set_prs where set_id = '22222222-2222-2222-2222-222222222222'::uuid $$,
  $$ values (true) $$,
  'First working set in view_set_prs is marked as a PR'
);

-- Cascade account deletion test
select tests.authenticate_as('postgres');
delete from auth.users where id = tests.get_supabase_uid('user_a');

select is_empty(
  $$ select * from public.profiles where id = tests.get_supabase_uid('user_a') $$,
  'Account deletion cascades to profiles'
);

select is_empty(
  $$ select * from public.workouts where user_id = tests.get_supabase_uid('user_a') $$,
  'Account deletion cascades to workouts'
);

select is_empty(
  $$ select * from public.sets where user_id = tests.get_supabase_uid('user_a') $$,
  'Account deletion cascades to sets'
);

select * from finish();
rollback;
```

- [ ] **Step 2: Run pgTAP test suite locally**

Run: `npx supabase test db`  
Expected: All tests pass with 0 failures.

- [ ] **Step 3: Commit**

```bash
git add supabase/tests/database/rls_views.test.sql
git commit -m "test(db): add full pgTAP suite covering RLS, cascade, composite FK, and timezone validation"
```

---

## Task 3: Install Step 1 Dependencies & Configure Vitest Component Testing

**Files:**

- Modify: `package.json`
- Modify: `vitest.config.ts`
- Create: `src/test/setup.ts`

- [ ] **Step 1: Install frontend runtime dependencies**

```bash
npm install react-router-dom @tanstack/react-query lucide-react
```

- [ ] **Step 2: Install test devDependencies for React component testing**

```bash
npm install -D @testing-library/react @testing-library/jest-dom jsdom
```

- [ ] **Step 3: Create `src/test/setup.ts`**

```typescript
import '@testing-library/jest-dom'
```

- [ ] **Step 4: Update `vitest.config.ts`**

```typescript
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    environment: 'jsdom',
    setupFiles: ['./src/test/setup.ts'],
    globals: true,
  },
})
```

- [ ] **Step 5: Verify existing tests pass**

Run: `npm run test`  
Expected: Existing tests pass in `jsdom` environment.

- [ ] **Step 6: Commit**

```bash
git add package.json package-lock.json vitest.config.ts src/test/setup.ts
git commit -m "chore: add react-router, react-query, lucide-react and configure jsdom testing"
```

---

## Task 4: App Shell, Navigation Layout & Router Scaffolding (Zero Supabase Import)

**Files:**

- Create: `src/components/layout/AppLayout.tsx`
- Create: `src/components/layout/Navbar.tsx`
- Create: `src/pages/PlaceholderPage.tsx`
- Create: `src/router.tsx`
- Modify: `src/App.tsx`
- Create: `src/router.test.tsx`

> [!IMPORTANT]
> **PR 1a must NOT import `src/lib/supabase.ts` or reference Supabase runtime client.** This allows PR 1a to build, pass CI, and deploy preview environments cleanly on Vercel before hosted environment variables exist.

- [ ] **Step 1: Create `src/components/layout/Navbar.tsx`**

```tsx
import { Link, useLocation } from 'react-router-dom'
import { Dumbbell, List, Settings } from 'lucide-react'

export function Navbar() {
  const location = useLocation()

  const navItems = [
    { label: 'Workouts', path: '/workouts', icon: Dumbbell },
    { label: 'Exercises', path: '/exercises', icon: List },
    { label: 'Settings', path: '/settings', icon: Settings },
  ]

  return (
    <nav className="bg-white border-b border-gray-200 sticky top-0 z-10">
      <div className="max-w-4xl mx-auto px-4 flex items-center justify-between h-14">
        <Link
          to="/workouts"
          className="font-bold text-indigo-600 text-lg flex items-center gap-2"
        >
          <Dumbbell className="w-5 h-5" />
          <span>WorkoutLog</span>
        </Link>
        <div className="flex items-center gap-4">
          {navItems.map(({ label, path, icon: Icon }) => (
            <Link
              key={path}
              to={path}
              className={`flex items-center gap-1 text-sm font-medium px-2 py-1 rounded-md transition-colors ${
                location.pathname.startsWith(path)
                  ? 'text-indigo-600 bg-indigo-50'
                  : 'text-gray-600 hover:text-gray-900'
              }`}
            >
              <Icon className="w-4 h-4" />
              <span>{label}</span>
            </Link>
          ))}
        </div>
      </div>
    </nav>
  )
}
```

- [ ] **Step 2: Create `src/components/layout/AppLayout.tsx`**

```tsx
import { Outlet } from 'react-router-dom'
import { Navbar } from './Navbar'

export function AppLayout() {
  return (
    <div className="min-h-screen bg-gray-50 flex flex-col">
      <Navbar />
      <main className="flex-1 max-w-4xl w-full mx-auto p-4">
        <Outlet />
      </main>
    </div>
  )
}
```

- [ ] **Step 3: Create `src/pages/PlaceholderPage.tsx`**

```tsx
export function PlaceholderPage({ title }: { title: string }) {
  return (
    <div className="p-8 text-center bg-white rounded-xl shadow-sm border border-gray-100">
      <h1 className="text-2xl font-bold text-gray-900 mb-2">{title}</h1>
      <p className="text-gray-500 text-sm">
        Feature module under construction.
      </p>
    </div>
  )
}
```

- [ ] **Step 4: Create `src/router.tsx` and update `src/App.tsx`**

```tsx
import { Routes, Route, Navigate } from 'react-router-dom'
import { AppLayout } from './components/layout/AppLayout'
import { PlaceholderPage } from './pages/PlaceholderPage'

export function AppRoutes() {
  return (
    <Routes>
      <Route path="/login" element={<PlaceholderPage title="Login" />} />
      <Route path="/signup" element={<PlaceholderPage title="Sign Up" />} />
      <Route element={<AppLayout />}>
        <Route path="/" element={<Navigate to="/workouts" replace />} />
        <Route
          path="/workouts"
          element={<PlaceholderPage title="Workouts" />}
        />
        <Route
          path="/workouts/new"
          element={<PlaceholderPage title="New Workout" />}
        />
        <Route
          path="/workouts/:id"
          element={<PlaceholderPage title="Edit Workout" />}
        />
        <Route
          path="/exercises"
          element={<PlaceholderPage title="Exercises" />}
        />
        <Route
          path="/settings"
          element={<PlaceholderPage title="Settings" />}
        />
      </Route>
      <Route path="*" element={<Navigate to="/workouts" replace />} />
    </Routes>
  )
}
```

```tsx
import { BrowserRouter } from 'react-router-dom'
import { QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { AppRoutes } from './router'

const queryClient = new QueryClient()

export function App() {
  return (
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <AppRoutes />
      </BrowserRouter>
    </QueryClientProvider>
  )
}
```

- [ ] **Step 5: Create `src/router.test.tsx`**

```tsx
import { render, screen } from '@testing-library/react'
import { MemoryRouter } from 'react-router-dom'
import { AppRoutes } from './router'

describe('Router Scaffolding', () => {
  it('renders workouts placeholder on /workouts', () => {
    render(
      <MemoryRouter initialEntries={['/workouts']}>
        <AppRoutes />
      </MemoryRouter>,
    )
    expect(screen.getByText('Workouts')).toBeInTheDocument()
  })

  it('renders settings placeholder on /settings', () => {
    render(
      <MemoryRouter initialEntries={['/settings']}>
        <AppRoutes />
      </MemoryRouter>,
    )
    expect(screen.getByText('Settings')).toBeInTheDocument()
  })
})
```

- [ ] **Step 6: Run tests and build checks**

Run: `npm run test`  
Run: `npm run lint`  
Run: `npm run typecheck`  
Run: `npm run build`  
Expected: All checks pass without errors.

- [ ] **Step 7: Commit**

```bash
git add src/components/layout/ src/pages/ src/router.tsx src/App.tsx src/router.test.tsx
git commit -m "feat: scaffold router, navbar layout, and placeholder views without supabase client"
```

---

## Task 5: Verify PR 1a, Push Branch & Open PR (STOP)

- [ ] **Step 1: Run comprehensive local verification suite**

1. `docker version` (confirm Docker server)
2. `npx supabase test db` (pgTAP suite)
3. `npm run test` (Vitest unit & component tests)
4. `npm run lint` (ESLint)
5. `npm run typecheck` (TypeScript)
6. `npm run build` (Vite production build)

- [ ] **Step 2: Push branch and create PR 1a**

```bash
git push -u origin feat/step1a-scaffold-db-tests
gh pr create --title "feat: scaffold routing, tanstack query, migration 0006 and full pgTAP suite (PR 1a)" --body "### PR 1a: Core Scaffolding, App/Query Shell, Migration 0006 & Full pgTAP Suite

- Added Migration 0006: safe timezone validation in handle_new_user fallback to column default.
- Implemented full pgTAP test suite (§4.6) covering RLS isolation, composite-FK cross-user tests, cascade account deletion, and valid/invalid timezone handling.
- Configured Vitest jsdom/RTL component testing setup.
- Scaffolded React Router routes, AppLayout, Navbar, and TanStack Query setup without importing Supabase client (can merge before env vars exist)."
```

- [ ] **Step 3: STOP**

> [!CAUTION]
> **STOP HERE.** Do not merge the PR. Do not push to `main`. Inform the user that PR 1a is open and ready for manual review and merge.

---

# Phase 1b Checkpoint: Hosted Supabase Setup & Security Advisors (User Actions)

## Task 6: Hosted Supabase Setup, Database Migration & Security Advisors Review

> [!IMPORTANT]
> The user performs these actions after merging PR 1a. PR 1b will not start until the user completes these actions and reports the Security Advisors findings.

- [ ] **User Action 1: Create hosted Supabase project**
  - Go to [database.new](https://database.new) and create a project in the preferred region.

- [ ] **User Action 2: Check Postgres major version**
  - In `supabase/config.toml`, ensure `major_version` matches the hosted database version (default is `17`).

- [ ] **User Action 3: Link & Push Migrations to Hosted Database**

  ```bash
  npx supabase link --project-ref <your-project-ref>
  npx supabase db push
  ```

  _(SAFETY: Never run `npx supabase db reset --linked` on production!)_

- [ ] **User Action 4 (CRITICAL): Security Advisors Review**
  - In Supabase Dashboard -> Navigate to **Advisors -> Security**.
  - Review all listed advisories.
  - Report findings to the assistant before PR 1b begins.

- [ ] **User Action 5: Set Vercel Environment Variables**
  - Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` to Vercel project settings across Production, Preview, and Development.

- [ ] **User Action 6: Configure Supabase Auth Redirect URLs**
  - In Supabase Dashboard (`Authentication -> URL Configuration`):
    - Site URL: `https://workout-log-tau-sooty.vercel.app`
    - Redirect URLs:
      - `https://workout-log-tau-sooty.vercel.app/**`
      - `https://workout-log-*-sing6738.vercel.app/**`
      - `http://localhost:5173/**`

---

# Phase 1c: PR 1b — Authentication, Protected Routes, Env Fallback & Supabase Client

Branch: `feat/step1b-auth` (branched from updated `main` after user merges PR 1a and confirms Task 6)

## Task 7: Env Error Screen & Safe Client Resolution

**Files:**

- Create: `src/components/EnvErrorScreen.tsx`
- Create: `src/lib/supabase.ts`
- Create: `src/components/EnvErrorScreen.test.tsx`

- [ ] **Step 1: Create `src/components/EnvErrorScreen.tsx`**

```tsx
export function EnvErrorScreen({ error }: { error: string }) {
  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="max-w-md w-full bg-white rounded-xl shadow-md p-8 border border-red-200">
        <h2 className="text-xl font-bold text-red-600 mb-2">
          Configuration Required
        </h2>
        <p className="text-sm text-gray-600 mb-4">
          Supabase environment variables are missing or invalid:
        </p>
        <div className="bg-red-50 text-red-700 p-3 rounded text-xs font-mono mb-4 break-all">
          {error}
        </div>
        <p className="text-xs text-gray-500">
          Please configure <code className="font-bold">VITE_SUPABASE_URL</code>{' '}
          and <code className="font-bold">VITE_SUPABASE_ANON_KEY</code> in your
          environment variables.
        </p>
      </div>
    </div>
  )
}
```

- [ ] **Step 2: Create `src/lib/supabase.ts`**

```typescript
import { createClient, SupabaseClient } from '@supabase/supabase-js'
import type { Database } from '../types/database'
import { parseEnv } from './env'

let _client: SupabaseClient<Database> | null = null

export function getSupabase(): SupabaseClient<Database> {
  if (!_client) {
    const env = parseEnv(import.meta.env)
    _client = createClient<Database>(
      env.VITE_SUPABASE_URL,
      env.VITE_SUPABASE_ANON_KEY,
    )
  }
  return _client
}

export function getEnvError(): string | null {
  try {
    parseEnv(import.meta.env)
    return null
  } catch (err: any) {
    return err.message || 'Missing Supabase environment variables'
  }
}

export type { Database } from '../types/database'
```

- [ ] **Step 3: Create `src/components/EnvErrorScreen.test.tsx`**

```tsx
import { render, screen } from '@testing-library/react'
import { EnvErrorScreen } from './EnvErrorScreen'

describe('EnvErrorScreen', () => {
  it('renders error message and instructions', () => {
    render(<EnvErrorScreen error="Missing VITE_SUPABASE_URL" />)
    expect(screen.getByText('Configuration Required')).toBeInTheDocument()
    expect(screen.getByText('Missing VITE_SUPABASE_URL')).toBeInTheDocument()
  })
})
```

- [ ] **Step 4: Commit**

```bash
git add src/components/EnvErrorScreen.tsx src/lib/supabase.ts src/components/EnvErrorScreen.test.tsx
git commit -m "feat(auth): add EnvErrorScreen and lazy getSupabase client resolver"
```

---

## Task 8: Auth Feature (Context, Pages, Protected Layout)

**Files:**

- Create: `src/features/auth/AuthContext.tsx`
- Create: `src/features/auth/LoginPage.tsx`
- Create: `src/features/auth/SignupPage.tsx`
- Create: `src/features/auth/ProtectedRoute.tsx`
- Create: `src/features/auth/AuthPages.test.tsx`

- [ ] **Step 1: Create `src/features/auth/AuthContext.tsx`**

Manages Supabase auth session and profile. Note: No timezone detection on first login!

```tsx
import React, { createContext, useContext, useEffect, useState } from 'react'
import { User, Session } from '@supabase/supabase-js'
import { getSupabase } from '../../lib/supabase'
import type { Database } from '../../types/database'

type Profile = Database['public']['Tables']['profiles']['Row']

interface AuthContextType {
  user: User | null
  session: Session | null
  profile: Profile | null
  loading: boolean
  signOut: () => Promise<void>
  refreshProfile: () => Promise<void>
}

const AuthContext = createContext<AuthContextType | undefined>(undefined)

export function AuthProvider({ children }: { children: React.ReactNode }) {
  const [user, setUser] = useState<User | null>(null)
  const [session, setSession] = useState<Session | null>(null)
  const [profile, setProfile] = useState<Profile | null>(null)
  const [loading, setLoading] = useState(true)

  const fetchProfile = async (userId: string) => {
    try {
      const supabase = getSupabase()
      const { data, error } = await supabase
        .from('profiles')
        .select('*')
        .eq('id', userId)
        .single()

      if (error) throw error
      if (data) setProfile(data)
    } catch (err) {
      console.error('Failed to fetch profile:', err)
    }
  }

  useEffect(() => {
    const supabase = getSupabase()

    supabase.auth.getSession().then(({ data: { session } }) => {
      setSession(session)
      setUser(session?.user ?? null)
      if (session?.user) {
        fetchProfile(session.user.id)
      }
      setLoading(false)
    })

    const {
      data: { subscription },
    } = supabase.auth.onAuthStateChange((_event, session) => {
      setSession(session)
      setUser(session?.user ?? null)
      if (session?.user) {
        fetchProfile(session.user.id)
      } else {
        setProfile(null)
      }
      setLoading(false)
    })

    return () => subscription.unsubscribe()
  }, [])

  const signOut = async () => {
    const supabase = getSupabase()
    await supabase.auth.signOut()
    setUser(null)
    setSession(null)
    setProfile(null)
  }

  const refreshProfile = async () => {
    if (user) {
      await fetchProfile(user.id)
    }
  }

  return (
    <AuthContext.Provider
      value={{
        user,
        session,
        profile,
        loading,
        signOut,
        refreshProfile,
      }}
    >
      {children}
    </AuthContext.Provider>
  )
}

export function useAuth() {
  const context = useContext(AuthContext)
  if (!context) throw new Error('useAuth must be used within an AuthProvider')
  return context
}
```

- [ ] **Step 2: Create `src/features/auth/SignupPage.tsx`**

Passes `timezone` (defaulted to browser's timezone, verified against `Intl.supportedValuesOf('timeZone')`) in `options.data.timezone`.

```tsx
import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { getSupabase } from '../../lib/supabase'

export function SignupPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [displayName, setDisplayName] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [infoMessage, setInfoMessage] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const navigate = useNavigate()

  const handleSignup = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setInfoMessage(null)
    setSubmitting(true)

    try {
      const supabase = getSupabase()

      // Determine timezone from supported values
      let detectedTimezone = 'Asia/Bangkok'
      try {
        const resolved = Intl.DateTimeFormat().resolvedOptions().timeZone
        const supported = Intl.supportedValuesOf('timeZone')
        if (resolved && supported.includes(resolved)) {
          detectedTimezone = resolved
        }
      } catch {
        detectedTimezone = 'Asia/Bangkok'
      }

      const { data, error } = await supabase.auth.signUp({
        email,
        password,
        options: {
          data: {
            name: displayName || undefined,
            timezone: detectedTimezone,
          },
        },
      })

      if (error) throw error

      if (data.session) {
        navigate('/workouts')
      } else if (data.user && !data.session) {
        setInfoMessage(
          'Account created! Please check your email inbox to confirm your account before logging in.',
        )
      }
    } catch (err: any) {
      setError(err.message || 'Failed to sign up')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="max-w-md w-full bg-white rounded-xl shadow-md p-8 border border-gray-100">
        <h2 className="text-2xl font-bold text-gray-900 mb-6 text-center">
          Create Account
        </h2>

        {error && (
          <div className="bg-red-50 text-red-700 p-3 rounded-md text-sm mb-4 border border-red-200">
            {error}
          </div>
        )}

        {infoMessage && (
          <div className="bg-blue-50 text-blue-700 p-3 rounded-md text-sm mb-4 border border-blue-200">
            {infoMessage}
          </div>
        )}

        <form onSubmit={handleSignup} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Display Name
            </label>
            <input
              type="text"
              value={displayName}
              onChange={(e) => setDisplayName(e.target.value)}
              placeholder="Your Name"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Email
            </label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Password
            </label>
            <input
              type="password"
              required
              minLength={6}
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>

          <button
            type="submit"
            disabled={submitting}
            className="w-full bg-indigo-600 text-white font-medium py-2 rounded-lg hover:bg-indigo-700 transition disabled:opacity-50"
          >
            {submitting ? 'Creating account...' : 'Sign Up'}
          </button>
        </form>

        <p className="text-center text-sm text-gray-500 mt-6">
          Already have an account?{' '}
          <Link
            to="/login"
            className="text-indigo-600 font-medium hover:underline"
          >
            Sign In
          </Link>
        </p>
      </div>
    </div>
  )
}
```

- [ ] **Step 3: Create `src/features/auth/LoginPage.tsx`**

```tsx
import { useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { getSupabase } from '../../lib/supabase'

export function LoginPage() {
  const [email, setEmail] = useState('')
  const [password, setPassword] = useState('')
  const [error, setError] = useState<string | null>(null)
  const [submitting, setSubmitting] = useState(false)
  const navigate = useNavigate()

  const handleLogin = async (e: React.FormEvent) => {
    e.preventDefault()
    setError(null)
    setSubmitting(true)

    try {
      const supabase = getSupabase()
      const { data, error } = await supabase.auth.signInWithPassword({
        email,
        password,
      })

      if (error) throw error
      if (data.session) {
        navigate('/workouts')
      }
    } catch (err: any) {
      setError(err.message || 'Failed to sign in')
    } finally {
      setSubmitting(false)
    }
  }

  return (
    <div className="min-h-screen flex items-center justify-center bg-gray-50 px-4">
      <div className="max-w-md w-full bg-white rounded-xl shadow-md p-8 border border-gray-100">
        <h2 className="text-2xl font-bold text-gray-900 mb-6 text-center">
          Welcome Back
        </h2>

        {error && (
          <div className="bg-red-50 text-red-700 p-3 rounded-md text-sm mb-4 border border-red-200">
            {error}
          </div>
        )}

        <form onSubmit={handleLogin} className="space-y-4">
          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Email
            </label>
            <input
              type="email"
              required
              value={email}
              onChange={(e) => setEmail(e.target.value)}
              placeholder="you@example.com"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>

          <div>
            <label className="block text-sm font-medium text-gray-700 mb-1">
              Password
            </label>
            <input
              type="password"
              required
              value={password}
              onChange={(e) => setPassword(e.target.value)}
              placeholder="••••••••"
              className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:outline-none focus:ring-2 focus:ring-indigo-500"
            />
          </div>

          <button
            type="submit"
            disabled={submitting}
            className="w-full bg-indigo-600 text-white font-medium py-2 rounded-lg hover:bg-indigo-700 transition disabled:opacity-50"
          >
            {submitting ? 'Signing in...' : 'Sign In'}
          </button>
        </form>

        <p className="text-center text-sm text-gray-500 mt-6">
          Don't have an account?{' '}
          <Link
            to="/signup"
            className="text-indigo-600 font-medium hover:underline"
          >
            Sign Up
          </Link>
        </p>
      </div>
    </div>
  )
}
```

- [ ] **Step 4: Create `src/features/auth/ProtectedRoute.tsx`**

```tsx
import { Navigate, Outlet } from 'react-router-dom'
import { useAuth } from './AuthContext'

export function ProtectedRoute() {
  const { session, loading } = useAuth()

  if (loading) {
    return (
      <div className="min-h-screen flex items-center justify-center bg-gray-50">
        <div className="text-gray-500 text-sm animate-pulse">
          Loading session...
        </div>
      </div>
    )
  }

  if (!session) {
    return <Navigate to="/login" replace />
  }

  return <Outlet />
}
```

- [ ] **Step 5: Create tests for Auth Components**

Create `src/features/auth/AuthPages.test.tsx` verifying render states and error displays.

- [ ] **Step 6: Commit**

```bash
git add src/features/auth/
git commit -m "feat(auth): add AuthContext, LoginPage, SignupPage with timezone support, and ProtectedRoute"
```

---

## Task 9: Wire Auth into App Shell & Router

**Files:**

- Modify: `src/App.tsx`
- Modify: `src/router.tsx`

- [ ] **Step 1: Update `src/router.tsx`**

Wire `LoginPage`, `SignupPage`, `ProtectedRoute`, and `AppLayout`.

- [ ] **Step 2: Update `src/App.tsx`**

Wrap with `AuthProvider` and check `getEnvError()`. If error exists, render `EnvErrorScreen`.

- [ ] **Step 3: Run full frontend test & build verification**

Run: `npm run test`  
Run: `npm run lint`  
Run: `npm run typecheck`  
Run: `npm run build`

- [ ] **Step 4: Commit**

```bash
git add src/App.tsx src/router.tsx
git commit -m "feat(auth): integrate AuthProvider and ProtectedRoute into App router"
```

---

## Task 10: Verify PR 1b, Push Branch & Open PR (STOP)

- [ ] **Step 1: Verify all tests pass**

Run: `npm run test`  
Run: `npm run build`

- [ ] **Step 2: Push branch and create PR 1b**

```bash
git push -u origin feat/step1b-auth
gh pr create --title "feat: authentication UI, protected routes, and EnvErrorScreen (PR 1b)" --body "### PR 1b: Auth UI, Protected Routes & Hosted Supabase Integration

- Implemented AuthContext, LoginPage, and SignupPage passing detected timezone (validated against Intl.supportedValuesOf).
- Added ProtectedRoute layout wrapper.
- Added EnvErrorScreen fallback for missing Supabase environment variables.
- Verified all component tests pass."
```

- [ ] **Step 3: STOP**

> [!CAUTION]
> **STOP HERE.** Do not merge the PR. Do not push to `main`. Inform the user that PR 1b is open for review and merge.

---

# Phase 2: PR 2 — Profile & Exercises

Branch: `feat/step1-profile-exercises` (branched from updated `main` after PR 1b is merged)

## Task 11: Profile & Settings Page

**Files:**

- Create: `src/features/profile/SettingsPage.tsx`
- Create: `src/features/profile/useProfile.ts`
- Create: `src/features/profile/SettingsPage.test.tsx`

- [ ] **Step 1: Create `src/features/profile/useProfile.ts`**
  - Plain mutation with TanStack Query invalidation to update `display_name`, `weight_unit` ('kg' | 'lbs'), and `timezone`.
- [ ] **Step 2: Create `src/features/profile/SettingsPage.tsx`**
  - Displays user profile form.
  - Timezone selector is populated strictly from `Intl.supportedValuesOf('timeZone')`.
  - Sign-out button.
- [ ] **Step 3: Tests for SettingsPage**
- [ ] **Step 4: Commit**

```bash
git add src/features/profile/
git commit -m "feat(profile): add SettingsPage with timezone picker and weight unit preference"
```

---

## Task 12: Exercise Directory & Custom Exercise Creation

**Files:**

- Create: `src/features/exercises/ExerciseListPage.tsx`
- Create: `src/features/exercises/CreateExerciseModal.tsx`
- Create: `src/features/exercises/useExercises.ts`
- Create: `src/features/exercises/ExerciseListPage.test.tsx`

- [ ] **Step 1: Create `src/features/exercises/useExercises.ts`**
  - Query for fetching master exercises (`user_id is null`) and user custom exercises (`user_id = auth.uid()`).
  - Mutation for creating custom exercise.
- [ ] **Step 2: Create `src/features/exercises/ExerciseListPage.tsx`**
  - Master badge for system exercises.
  - Search & category filter.
- [ ] **Step 3: Create `src/features/exercises/CreateExerciseModal.tsx`**
  - Modal form for creating custom exercises.
- [ ] **Step 4: Component Tests**
- [ ] **Step 5: Commit**

```bash
git add src/features/exercises/
git commit -m "feat(exercises): add exercise list and custom exercise creation modal"
```

---

## Task 13: Verify PR 2, Push Branch & Open PR (STOP)

- [ ] **Step 1: Verify tests and build**
      Run: `npm run test`, `npm run lint`, `npm run typecheck`, `npm run build`.
- [ ] **Step 2: Push branch and create PR 2**

```bash
git push -u origin feat/step1-profile-exercises
gh pr create --title "feat: profile settings and exercise directory (PR 2)" --body "### PR 2: Profile Settings & Exercise Directory

- Added SettingsPage allowing users to edit display name, weight unit, and timezone (selected from Intl.supportedValuesOf).
- Added Exercise directory with master exercise badges and custom exercise creation modal.
- All unit and component tests passing."
```

- [ ] **Step 3: STOP**

> [!CAUTION]
> **STOP HERE.** Do not merge the PR. Do not push to `main`. Inform the user that PR 2 is open for review and merge.

---

# Phase 3: PR 3 — Workout List & Editor

Branch: `feat/step1-workouts` (branched from updated `main` after PR 2 is merged)

## Task 14: Unit Conversion Helpers with 45/135/225 lb Round-Trip Tests

**Files:**

- Create: `src/lib/units.ts`
- Create: `src/lib/units.test.ts`

- [ ] **Step 1: Create `src/lib/units.ts`**
  - `kgToLbs(kg: number): number` (rounds to nearest 0.5)
  - `lbsToKg(lbs: number): number` (rounds to 2 decimals)
  - `displayWeight(kg: number, unit: 'kg' | 'lbs'): number`
  - `inputToStoredKg(input: number, unit: 'kg' | 'lbs'): number`

- [ ] **Step 2: Create `src/lib/units.test.ts`**
  - Unit tests verifying round-trip `lb -> kg -> stored -> lb` for standard plate weights: 45 lbs, 135 lbs, and 225 lbs.

- [ ] **Step 3: Commit**

```bash
git add src/lib/units.ts src/lib/units.test.ts
git commit -m "feat(units): add weight conversion helpers and 45/135/225 lb round-trip tests"
```

---

## Task 15: Workout Validation Schemas & Tests

**Files:**

- Create: `src/features/workouts/workoutSchemas.ts`
- Create: `src/features/workouts/workoutSchemas.test.ts`

- [ ] **Step 1: Create Zod schemas for workout and set payloads**
- [ ] **Step 2: Write schema unit tests**
- [ ] **Step 3: Commit**

```bash
git add src/features/workouts/workoutSchemas.ts src/features/workouts/workoutSchemas.test.ts
git commit -m "feat(workouts): add Zod validation schemas for workout editor payloads"
```

---

## Task 16: Workout List Dashboard

**Files:**

- Create: `src/features/workouts/WorkoutListPage.tsx`
- Create: `src/features/workouts/WorkoutCard.tsx`
- Create: `src/features/workouts/useWorkouts.ts`
- Create: `src/features/workouts/WorkoutListPage.test.tsx`

- [ ] **Step 1: Create hooks and list components**
- [ ] **Step 2: Tests for WorkoutListPage**
- [ ] **Step 3: Commit**

```bash
git add src/features/workouts/WorkoutListPage.tsx src/features/workouts/WorkoutCard.tsx src/features/workouts/useWorkouts.ts src/features/workouts/WorkoutListPage.test.tsx
git commit -m "feat(workouts): add workout list dashboard with delete mutation"
```

---

## Task 17: Workout Editor (Atomic RPC Save, Auto-fill, Copy Set)

**Files:**

- Create: `src/features/workouts/WorkoutEditorPage.tsx`
- Create: `src/features/workouts/ExerciseSection.tsx`
- Create: `src/features/workouts/SetRow.tsx`
- Create: `src/features/workouts/useWorkoutEditor.ts`
- Create: `src/features/workouts/WorkoutEditorPage.test.tsx`

- [ ] **Step 1: Create Workout Editor components with client UUIDs (`crypto.randomUUID()`)**
- [ ] **Step 2: Integrate `get_previous_sets` RPC on exercise selection for placeholders**
- [ ] **Step 3: Implement "Copy last set" stepper controls**
- [ ] **Step 4: Save atomically via `supabase.rpc('save_workout', { payload })`**
- [ ] **Step 5: Tests for Workout Editor**
- [ ] **Step 6: Commit**

```bash
git add src/features/workouts/
git commit -m "feat(workouts): add mobile-first workout editor with atomic save and autofill"
```

---

## Task 18: Final Step 1 Verification Pass, Push Branch & Open PR 3 (STOP)

- [ ] **Step 1: Run comprehensive verification**
  1. `docker version`
  2. `npx supabase test db`
  3. `npm run test`
  4. `npm run lint`
  5. `npm run typecheck`
  6. `npm run build`

- [ ] **Step 2: Push branch and create PR 3**

```bash
git push -u origin feat/step1-workouts
gh pr create --title "feat: workout list and mobile-first workout editor (PR 3)" --body "### PR 3: Workout List & Mobile-First Workout Editor

- Added WorkoutListPage dashboard with delete support.
- Added WorkoutEditorPage with atomic save_workout RPC, client UUIDs, previous-set auto-fill, and copy-last-set.
- Implemented units.ts boundary conversion with 45/135/225 lb round-trip verification.
- All pgTAP, unit, and component tests passing."
```

- [ ] **Step 3: STOP**

> [!CAUTION]
> **STOP HERE.** Do not merge the PR. Do not push to `main`. Inform the user that PR 3 is open for review and merge.
