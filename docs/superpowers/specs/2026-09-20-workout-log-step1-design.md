# Workout Log — Step 1 Design Spec

**Date**: 2026-09-20  
**Project**: Workout Log (Full-stack weight-training log)  
**Step**: 1 — Core CRUD & Auth Foundation

---

## 1. Scope & Objective

Implement **Step 1** as defined in `PROJECT_SPEC.md` (§5, §7), structured across **4 sequential Pull Requests (PR 1a, PR 1b, PR 2, PR 3)**:

- **Scaffolding & Database Testing (PR 1a)**: Migration `0006_handle_new_user_timezone.sql`, full pgTAP test suite from `PROJECT_SPEC.md` §4.6 (RLS isolation, composite-FK cross-user test, account-deletion cascade test, valid/invalid timezone handling in `handle_new_user`), Vitest jsdom/RTL setup, React Router and TanStack Query scaffolding with placeholder routes. **Must not import `src/lib/supabase.ts`**, allowing it to merge before any environment variables exist.
- **Hosted Supabase Link & Security Checkpoint (User Actions)**: Hosted Supabase project creation, link, `db push`, and User review of Supabase Dashboard -> Advisors -> Security before PR 1b starts.
- **Authentication & App Integration (PR 1b)**: Email/password sign-up (passing timezone in `options.data.timezone` via `Intl.supportedValuesOf('timeZone')`), sign-in, sign-out, session persistence via Supabase Auth, protected route wrappers, fallback UI for missing environment variables (`EnvErrorScreen`), and auth redirect URLs for Vercel production & preview environments.
- **Profile & Exercises (PR 2)**: Read/update user profile (`display_name`, `weight_unit` ['kg', 'lbs'], `timezone` selected from `Intl.supportedValuesOf('timeZone')`), exercise directory (master exercises with system badge, custom exercise creation).
- **Workout Editor & CRUD (PR 3)**: Workout list, mobile-first workout editor with client UUIDs (`crypto.randomUUID()`), Zod payload validation, atomic save via `supabase.rpc('save_workout')`, previous-set auto-fill via `get_previous_sets`, copy-last-set, and display unit conversion at UI/RPC boundaries.
- **Testing**: Full pgTAP suite (§4.6) for RLS isolation and atomic semantics, Vitest + React Testing Library (`@testing-library/react`, `jsdom`) for UI components, and unit round-trip tests for weight conversion.

### Out of Scope for Step 1:

- Forgot-password flow, email change flow, and anonymous sign-in (revisited in Step 5).
- Custom exercise deletion (deferred because `sets.exercise_id` has `on delete no action`).
- Optimistic updates & offline sync queue (deferred to Step 4).
- Playwright e2e testing (deferred to Step 5).

---

## 2. Tech Stack & State Management

| Area                 | Choice                                                           | Rationale                                                                   |
| -------------------- | ---------------------------------------------------------------- | --------------------------------------------------------------------------- |
| Routing              | `react-router-dom` (v6)                                          | Client-side routing with protected layout route pattern                     |
| Server State         | `@tanstack/react-query` (v5)                                     | Plain mutations + query invalidation (no optimistic updates in Step 1)      |
| UI Component Testing | `@testing-library/react` + `@testing-library/jest-dom` + `jsdom` | Introduced only for Step 1 UI components requiring DOM simulation           |
| Database Testing     | pgTAP (`supabase test db`)                                       | Full RLS policy, trigger function, and stored procedure verification (§4.6) |
| Icons                | `lucide-react`                                                   | SVG icons for navigation, steppers, delete, copy actions                    |

---

## 3. Architecture & Routing

### 3.1 Route Hierarchy

```
/
├── /login                 (Public - redirects to /workouts if authenticated)
├── /signup                (Public - handles both instant login and email-confirmation states; passes timezone)
└── / (Protected Layout)   (Requires valid Supabase session; redirects to /login)
    ├── /workouts          (Workout List - default dashboard)
    ├── /workouts/new      (Workout Editor - create mode)
    ├── /workouts/:id      (Workout Editor - edit mode)
    ├── /exercises         (Exercise Directory - master + custom)
    └── /settings          (Profile & preferences - timezone dropdown from Intl.supportedValuesOf)
```

### 3.2 Env Error Boundary

If `VITE_SUPABASE_URL` or `VITE_SUPABASE_ANON_KEY` is missing or invalid when the app initializes, the app displays a clear error screen ("Configuration Error: Missing Supabase Environment Variables") instead of crashing with a blank white page.

---

## 4. Feature Details & Data Flow

### 4.1 Authentication & Profile Timezone Handling

- **Database Trigger Function (`handle_new_user`)**:
  - Defined in a **new migration `0006_handle_new_user_timezone.sql`** (never modify `0001`–`0005`).
  - Reads `raw_user_meta_data->>'name'` for `display_name`.
  - Reads `raw_user_meta_data->>'timezone'`.
  - Checks if `raw_user_meta_data->>'timezone'` exists in `pg_timezone_names`.
  - If valid, sets `profiles.timezone` to the provided timezone; otherwise falls back to the column default (`'Asia/Bangkok'`).
  - **Reason**: Database views rely on `at time zone p.timezone`. An invalid timezone string would fail Postgres timezone conversion and break every analytics query for that user.
- **Client Sign Up**:
  - The client obtains the user's timezone using `Intl.DateTimeFormat().resolvedOptions().timeZone` or allows selection strictly from `Intl.supportedValuesOf('timeZone')`.
  - Passed at signup: `supabase.auth.signUp({ email, password, options: { data: { name: displayName, timezone: detectedTimezone } } })`.
  - **No detection on first login**: The timezone is captured during sign-up; users can change it later on the settings page.
- **Sign In**: `supabase.auth.signInWithPassword({ email, password })`.
- **Email Confirmation Handling**: If email confirmation is disabled (development mode), the session is established immediately. If confirmation is enabled, UI displays a clear "Please check your inbox to confirm your email" notification.

### 4.2 Weight Unit Conversion (UI/RPC Boundary)

- **Database Storage**: All weights in `public.sets.weight_kg` are stored in kilograms (`numeric(6,2)`).
- **Client Conversion (`src/lib/units.ts`)**:
  - Conversion occurs strictly at the UI boundary.
  - When user preferred unit is `lbs`:
    - Displayed values are converted `kg -> lbs` and rounded to the nearest `0.5 lb`.
    - Input values in `lbs` are converted `lbs -> kg` and rounded to 2 decimals before being passed into `save_workout` payload.
  - Vitest test suite includes round-trip verification (`lb -> kg -> stored -> lb`) for standard plate weights: `45 lbs`, `135 lbs`, and `225 lbs`.

### 4.3 Exercises Directory

- Master exercises (`user_id IS NULL`) are displayed with a "Master" badge (read-only).
- User custom exercises (`user_id = auth.uid()`) can be created via modal.
- Custom exercise deletion is deferred (due to `ON DELETE NO ACTION` foreign key on `sets`).

### 4.4 Workout Editor

- Client generates UUIDs (`crypto.randomUUID()`) for workouts and sets.
- Payload validated with Zod (`WorkoutPayloadSchema`) prior to RPC invocation.
- `get_previous_sets` RPC invoked on exercise selection to populate previous weight/reps placeholders.
- "Copy last set" duplicates values of the previous set with an incremented `set_number`.
- Saved atomically via `supabase.rpc('save_workout', { payload })`.
- Plain mutations with TanStack Query invalidation on success.

---

## 5. Deployment, Hosted Supabase & Shared Previews

### 5.1 Infrastructure Sequencing & Security Review Checkpoint

User actions must be executed in this strict order:

1. Run `docker version` prior to PR 1a; if Docker Server is unavailable, stop and alert user immediately.
2. Complete and merge PR 1a (no Supabase client import, merges cleanly without env vars).
3. Create hosted Supabase project.
4. Check `major_version` in `supabase/config.toml` matches the hosted Postgres version.
5. Link and push migrations: `npx supabase link` -> `npx supabase db push`.
   - **SAFETY RULE**: NEVER run `npx supabase db reset --linked` on the production project.
6. **Security Review Checkpoint (User Action)**: User reviews **Supabase Dashboard -> Advisors -> Security** and shares the findings before PR 1b work begins.
7. Set Vercel environment variables (`VITE_SUPABASE_URL`, `VITE_SUPABASE_ANON_KEY`) across Production, Preview, and Development.
8. Only after env vars are active in Vercel and security advisor review is confirmed, start and merge PR 1b.

### 5.2 Auth Redirect URLs

In Supabase Dashboard (`Authentication -> URL Configuration`):

- **Site URL**: `https://workout-log-tau-sooty.vercel.app`
- **Redirect URLs**:
  - `https://workout-log-tau-sooty.vercel.app/**`
  - `https://workout-log-*-sing6738.vercel.app/**` (specifically scoped to user's Vercel account to prevent other projects matching)
  - `http://localhost:5173/**` (local development)

### 5.3 Shared Database in Previews

_Important Architectural Note_: All Vercel preview deployments share the hosted Supabase database with production. Multi-tenancy and data isolation between accounts are strictly enforced by Postgres Row Level Security (RLS).

---

## 6. PR Breakdown Strategy & Operating Rules

To maintain high code quality and verifiable checkpoints, Step 1 is executed across 4 sequential PRs:

- **PR 1a — Scaffolding, App/Query Shell, Migration 0006 & Full pgTAP Suite**:
  - Migration `0006_handle_new_user_timezone.sql` for safe timezone handling in `handle_new_user`.
  - Full pgTAP suite (§4.6) including RLS tests, composite-FK cross-user tests, account-deletion cascade tests, and valid/invalid timezone tests.
  - Setup React Router, TanStack Query, Lucide icons, Vitest jsdom setup.
  - Scaffolding route structure without importing `src/lib/supabase.ts`.
- **Hosted Supabase Link & Security Advisors Review (User Actions)**:
  - `npx supabase link` -> `npx supabase db push`.
  - User reviews Supabase Dashboard Security Advisors.
  - Vercel environment variables configuration.
- **PR 1b — Authentication, Protected Routes & Env Fallback**:
  - Auth context, login page, signup page (passing timezone with `Intl.supportedValuesOf('timeZone')`), protected route layout, env error screen.
  - Connect router to Supabase client.
- **PR 2 — Profile & Exercises**:
  - Profile settings page with timezone selection (`Intl.supportedValuesOf('timeZone')`) and weight unit preference.
  - Exercises list, search, category filter, and create custom exercise modal.
- **PR 3 — Workout List & Editor**:
  - Workout list dashboard with delete mutation.
  - Workout editor with atomic `save_workout`, client UUIDs, previous-set auto-fill, copy-last-set, and `units.ts` boundary conversions (with 45/135/225 lb round-trip tests).

### Non-Negotiable PR Process Rules

1. **Never merge**: For every PR, push the branch and open the PR using `gh pr create`, then **STOP**. The user merges PRs manually.
2. **Never push to main** directly.
3. **Never rewrite history** (no force push / rebasing published history).
4. **Local DB Verification**: Always check `docker version` before running local DB tests. If Docker Server is down, stop and alert user immediately.
