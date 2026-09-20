# Workout Log

Full-stack weight-training log built with React, TypeScript, Supabase, and Tailwind CSS v4.

## Prerequisites

- **Node.js 22** — see `.nvmrc`; use `nvm use` or `fnm use`
- **Docker Desktop** — required for local Supabase
- **GitHub CLI** (`gh`) — optional, for repo creation and CI monitoring

## Local Development

```bash
npm ci
npx supabase start
npx supabase db reset
npm run dev
```

### Environment Variables

Copy `.env.example` to `.env` and fill in values from `npx supabase status`:

```bash
cp .env.example .env
npx supabase status # copy API URL and anon key
```

### Available Scripts

| Script                 | Description                        |
| ---------------------- | ---------------------------------- |
| `npm run dev`          | Start Vite dev server              |
| `npm run build`        | Type-check + production build      |
| `npm run typecheck`    | TypeScript check (`tsc -b`)        |
| `npm run lint`         | ESLint                             |
| `npm run format:check` | Prettier check                     |
| `npm run test`         | Vitest                             |
| `npm run gen:types`    | Generate Supabase TypeScript types |
| `npm run check:types`  | Generate types + verify no diff    |

### Database

```bash
npx supabase start # start local Supabase (Docker)
npx supabase db reset # apply all migrations
npx supabase test db # run pgTAP tests
npx supabase stop # stop local Supabase
```

## CI

GitHub Actions runs on push/PR to `main`:

- **app** job: typecheck → lint → format:check → test → build
- **db** job: supabase start → db reset → test db → gen:types → upload types artifact → git diff --exit-code on src/types/database.ts

## Deployment

Vercel is now connected to this GitHub repo (production on `main`, preview per PR).

Live demo: https://workout-log-tau-sooty.vercel.app

- **Step 0** (current): No environment variables needed (no auth/API usage yet)
- **Step 1**: Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` in Vercel dashboard
