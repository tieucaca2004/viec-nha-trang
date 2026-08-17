# PHASE 2 REPORT — Backend Real Environment + E2E

Scope: turn the Phase 1 backend scaffold into a backend that actually runs, against a real
PostgreSQL database, with real migrations/seed, and E2E tests for the core recruitment flow.
No new product features. No AI, payment, Google/Apple login, or advanced maps.

## Environment note (read before the table)

Docker's daemon exists in this sandbox but has **no outbound registry access** (`docker compose up`
fails pulling `postgres:16-alpine` with `403 Forbidden` from the image CDN — a proxy/network policy
in this environment, not a config error). `docker-compose.yml` is committed and its config is valid
(compose parsed and started the pull correctly), but it was **not exercised end-to-end** here.
Instead, all verification below ran against **PostgreSQL 16 installed locally** (`pg_ctlcluster`),
which is a real, unmodified PostgreSQL server — the migrations, seed, boot, and E2E results are real,
just not run through the Docker Compose path. Anyone with normal Docker registry access should be
able to run `docker compose up -d` and get the same database.

## Results

| Area | Result | Notes |
|---|---|---|
| PostgreSQL | PASS (local, not Docker) | `docker-compose.yml` added (Postgres 16 + volume + healthcheck), config valid but registry-blocked in this sandbox; verified instead against local PostgreSQL 16 |
| Prisma schema | PASS | `prisma validate` clean; reviewed all 21 tables — FKs, unique constraints, indexes, enums, timestamps all consistent (see §3) |
| Migration | PASS | `20260817083932_init` generated via `prisma migrate dev`, applied cleanly, `prisma migrate deploy` confirms 1/1 applied, no pending |
| Seed | PASS | Ran twice; row counts identical both times (users=3, jobs=2, areas=17, categories=15) — idempotent |
| Backend boot | PASS | `nest start --watch` against real DB; boots clean, all 45 routes mapped, zero errors |
| Auth (OTP+JWT) | PASS | Live curl: OTP request → console-logged code → verify → JWT → `/me` returns real DB user |
| RBAC | PASS | Verified live and in E2E: 401 unauthenticated, 403 wrong role, ownership checks enforced server-side |
| Job seeker E2E | PASS | 9/9 tests: login, profile, search, filter, detail, save/unsave, apply, track status |
| Employer E2E | PASS | 8/8 tests: login+role switch, profile+location, publish job, reject missing salary, list mine, full applicant status pipeline NEW→VIEWED→CONTACTED→INTERVIEW→HIRED, close |
| Admin E2E | PASS | 6/6 tests: login, dashboard, list users/employers/jobs/applications/reports, category+area CRUD |
| Security | PASS | 11/11 tests: 401/403 distinction, forged JWT rejected, cross-tenant ownership blocked (job edit, applicant view, status change) with **data verified unchanged**, no duplicate applications, input validation, SQL injection payload harmless, passwordHash never leaks |
| Swagger | PASS | `/api/docs` live; JSON schema verified to reflect real DTO (`CreateJobDto` required fields, `@Min` constraints) via the `@nestjs/swagger` CLI plugin — not hand-written |
| Flutter | **BLOCKED** — `flutter: command not found` in this environment. Not attempted further per instructions. Dart code is unchanged from Phase 1. |
| Admin (Next.js) | PASS | `npm install && next build` — unchanged from Phase 1, still compiles clean (11/11 static pages) |
| E2E test suite | PASS | 4 suites, 34/34 tests, two consecutive full runs both green |

**Total: 34/34 E2E tests PASS. Flutter toolchain: BLOCKED (unavailable, not a code failure).**

## What was actually run (not just "it compiles")

```
npx prisma validate                     # schema valid
npx prisma migrate dev --name init      # migration created + applied to real DB
npx prisma migrate deploy               # 1 migration applied, none pending
npm run prisma:seed                     # x2, row counts identical both times
nest start --watch                      # real boot, 45 routes, live curl round-trips
npm run test:e2e                        # 4 suites / 34 tests, x2 runs, both green
next build (apps/admin)                 # 11/11 static pages
```

## Bugs found and fixed via real E2E (not present in Phase 1's compile-only checks)

Phase 1 only proved the code compiled and the server started with an empty DB. Running real
requests against a real database surfaced four defects that unit-level compilation could not:

1. **`passwordHash` leaked in API responses.** `GET /me` and `GET /admin/users` returned the
   raw Prisma `User` row including `passwordHash` (null today, but the field existed and was
   serialized). Fixed with explicit `select` in `users.service.ts` and `admin.service.ts`
   (`src/common/services/safe-select.ts`). A global Prisma `omit` config was tried first but
   did not reliably strip the field at runtime in this Prisma/client combination — reverted in
   favor of the explicit, verifiable `select` approach.

2. **Role switching didn't actually work.** `PATCH /me/roles` updates the DB, but the
   already-issued JWT's `roles` claim is frozen at login time, so `RolesGuard` kept rejecting
   the newly-granted `EMPLOYER` role until a fresh login. Fixed in `JwtStrategy.validate()` to
   read current roles from the DB on every request instead of trusting the token claim — this
   also means a banned/deleted user's existing token stops working immediately, which is the
   correct security behavior (mục 32).

3. **`latitude`/`longitude` were silently dropped from three DTOs**
   (`CreateEmployerLocationDto`, `UpsertJobSeekerProfileDto`, `QueryJobsDto`). They had
   `@Type(() => Number)` but no `class-validator` decorator, so Nest's
   `whitelist: true` stripped them before the handler ever saw them — creating an employer
   location (a required step before posting a job) failed with `400` on every request. Fixed
   by adding `@IsLatitude()`/`@IsLongitude()`/`@IsNumber()`.

4. **`isUrgent` query filter (🔥 "Đi làm ngay" quick filter) was broken.** It combined
   `@Type(() => Number)` with `@IsBoolean()`, which converts the query string to `NaN` before
   validating it as a boolean. Fixed with an explicit `@Transform` to a real boolean.

None of these were feature additions — all are bug fixes required to make already-specified
Phase 1 behavior (§5 role switching, §13 job posting, §9 quick filters, §32/33 privacy) actually
work when exercised end-to-end.

## Seed accounts (test/demo only, not real people)

| Role | Phone | Notes |
|---|---|---|
| Admin | `0900000001` | `roles: [ADMIN]` |
| Employer | `0900000002` | "Hủ Tiếu Xào A Tiểu", 1 location in Vĩnh Hải, 2 sample jobs |
| Job seeker | `0900000003` | Basic profile, desired category "Phục vụ" |

OTP codes are logged to console in development (`ConsoleSmsProvider`) — no real SMS is sent.

## Files changed

26 files changed (696 insertions, 26 deletions), plus new files:
`docker-compose.yml`, `apps/backend/prisma/migrations/20260817083932_init/`,
`apps/backend/src/common/services/safe-select.ts`, `apps/backend/test/` (5 spec/util files +
jest config + global setup). Full list via `git show --stat` on the Phase 2 commit.

## Blockers

- **Flutter SDK unavailable** in this environment. Mobile app code is unchanged from Phase 1
  and was not re-verified (`pub get`/`analyze`/`format`) in this phase. Needs a separate run
  in an environment with Flutter installed.
- **Docker registry unreachable** in this sandbox (proxy/network policy blocks the image CDN).
  `docker-compose.yml` is committed and config-valid but not exercised end-to-end here — verify
  it once in an environment with normal Docker registry access.

## Explicitly out of scope (per instructions) — logged to docs/ROADMAP.md, not implemented

AI job generation, payment gateways, Google/Apple login, advanced maps, realtime chat, AI
recommendation/matching, Redis, Elasticsearch, microservices, Kubernetes, production deployment.

## Conclusion

**PHASE 2 PASS** for everything within this environment's reach: real backend, real PostgreSQL
database, real migrations, idempotent seed, and 34/34 core E2E tests (job seeker, employer,
admin, security) green across two consecutive runs. Flutter verification is blocked by SDK
availability, not by a code defect — reported as BLOCKED, not PASS. This is not a claim of
"production ready" — see docs/ROADMAP.md for what's intentionally still missing.
