# ROADMAP — items noticed but intentionally NOT implemented

This file tracks things discovered during development that are out of scope for the current
phase, per explicit instruction not to expand scope without asking. Nothing here has been built.

## Explicitly deferred by Phase 2 instructions

- AI job-draft generation (mục 14) — stub endpoint already returns 501 from Phase 1, untouched.
- Real payment gateways: VNPay/MoMo/ZaloPay/IAP (mục 28) — `PaymentProvider` interface exists,
  no implementation.
- Google Sign-In / Apple Sign-In (mục 5) — stub methods throw `NotImplementedException`.
- Advanced maps (map view of nearby jobs, mục 18) — only lat/lng + haversine distance today.
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
