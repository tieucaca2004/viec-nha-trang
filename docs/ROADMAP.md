# ROADMAP — items noticed but intentionally NOT implemented

This file tracks things discovered during development that are out of scope for the current
phase, per explicit instruction not to expand scope without asking. Nothing here has been built.

## Explicitly deferred by Phase 2 instructions

- AI job-draft generation (mục 14) — stub endpoint already returns 501 from Phase 1, untouched.
- Real payment gateways: VNPay/MoMo/ZaloPay/IAP (mục 28) — `PaymentProvider` interface exists,
  no implementation.
- Google Sign-In / Apple Sign-In (mục 5) — stub methods throw `NotImplementedException`.
- Advanced maps (map view of nearby jobs, mục 18) — only lat/lng + haversine distance today.
- Interactive map picker for employer location (tap-on-map coordinate selection) — the FULL
  AUDIT remediation pass removed the hard-coded Nha Trang center coordinates and added real GPS +
  manual lat/lng entry as functioning alternatives (see `docs/MOBILE.md` "Audit remediation"),
  but a `google_maps_flutter`-style interactive picker still requires a real Maps API key +
  billing account that doesn't exist in this environment — same constraint as above.
- Realtime chat, AI recommendation/matching beyond the current rule-based `MatchScoreService`.
- Redis, Elasticsearch, microservices, Kubernetes, production deployment config.

## Found during Phase 2 but out of scope to fix now

- **Docker registry access.** This development sandbox cannot reach the Docker image CDN
  (403 from a CDN-signed URL, consistent with an environment network policy). `docker-compose.yml`
  is committed and config-valid; it should be smoke-tested once in an environment with normal
  registry access, but that's an infra/environment issue, not application code.
- **`nest start --watch` requires a full process restart, not just a file save, to pick up
  `nest-cli.json` changes** (e.g. enabling the `@nestjs/swagger` CLI plugin). This is standard
  Nest CLI behavior, not a bug — noting it here only because it cost debugging time and future
  contributors should know to restart (not just save) after touching `nest-cli.json`.
- **Global Prisma `omit` config didn't work as expected** in this Prisma/client version
  combination when tried as a way to globally hide `passwordHash`. Worked around with explicit
  `select` (see `src/common/services/safe-select.ts`) which is more verifiable anyway. Someone
  could investigate why the constructor-level `omit` option silently no-op'd, but the explicit
  `select` approach is arguably better practice regardless (obvious at every call site).
- **NestJS testing module's `overrideProvider(APP_GUARD)` / `overrideGuard()` did not disable
  the globally-registered `ThrottlerGuard`** in E2E tests in this Nest/@nestjs/throttler version
  combination (confirmed via a standalone repro script, not just test flakiness). Worked around
  by making the OTP throttle limits configurable via env vars (`OTP_REQUEST_THROTTLE_LIMIT`,
  `OTP_VERIFY_THROTTLE_LIMIT`), which is itself a small legitimate improvement (previously a
  hardcoded magic number). If a future contributor wants a "real" guard override for other
  E2E scenarios, this is worth revisiting.
- **Flutter mobile app was not re-verified in Phase 2** because the Flutter SDK is not available
  in this environment. `flutter pub get && flutter analyze && dart format --set-exit-if-changed .`
  needs to run in an environment that has Flutter installed before the mobile code can be
  trusted beyond "it was hand-written correctly" from Phase 1.

## Found during the master-prompt architecture-adaptation phase (kept NestJS+Postgres, see docs/PLAN.md)

- **k6 load test script (`apps/backend/loadtest/scenarios.js`) doesn't cover "update application
  status"** — every other required scenario (search, filter, detail, apply, save, employer
  creates job, employer reads applicants, notifications) does. Adding it means having an
  employer VU look up an applicant that a different seeker VU just created and transition its
  status, which needs shared cross-VU state k6 doesn't give you for free — solvable, just not
  done here. See `docs/LOAD_TESTING.md`.
- **No load test has been run at the actual target scale** (100/500/1000/5000 concurrent per
  §6/§49) — only small smoke runs (10-20 VUs) against a single dev machine sharing CPU with
  Postgres. Needs a real Cloud Run + Cloud SQL deployment and a distributed k6 run (k6 Cloud or
  multiple VMs) to get meaningful numbers — see `docs/LOAD_TESTING.md` for exactly what was and
  wasn't proven by the runs that did happen.
- **Google/Apple Sign-In, real payment gateways, mobile-side image compression before upload,
  and object storage upload endpoints** remain unimplemented (interfaces/schema exist) — same
  status as Phase 1/2, unchanged by this phase.
- **No GCP project, Firebase project, or Cloud Run/Cloud SQL instance exists** for this app in
  this environment — `docs/DEPLOYMENT.md` is a runnable procedure, not something that has been
  executed. Same for Firebase Cloud Messaging: the backend-side integration is real and tested
  (falls back to a safe no-op without config), but no Firebase project has actually been created,
  so no push notification has ever really reached a device.
- **`GET /auth/otp/debug/:phone`** exists solely to make load testing possible without reading
  server logs. It self-disables in production and when the SMS provider isn't the console one,
  but it's still new attack surface that didn't exist before this phase — worth a second set of
  eyes before this code goes anywhere near a real deployment, even though it's guarded.

## Found during FULL AUDIT remediation (real GitHub Actions run, not sandbox)

- **`flutter build apk --debug` fails on real CI with a real Android SDK** (confirmed via GitHub
  Actions run 32045998356, not the sandbox's usual "no SDK" limitation) — `geolocator_android
  4.6.2`'s own `android/build.gradle` (third-party code in `.pub-cache`, not this project's code)
  is incompatible with the current Flutter Gradle Plugin loading mechanism. The real fix
  (`geolocator_android 5.0.3`) only ships bundled with `geolocator ^14.0.0`, which requires
  Flutter SDK ≥3.29 per its changelog — confirmed by trying a `dependency_overrides` workaround,
  which got past `pub get` but failed to compile (`Color.toARGB32()` needs Flutter ≥3.27,
  project is pinned to 3.24.5). Upgrading the Flutter SDK (local + CI) is out of scope for the
  audit-remediation pass that found this — it's a real toolchain decision that needs its own
  review, not a quick patch. See `docs/BUILD.md` for the full trace and both real fix options.
