# TESTING — VIỆC NHA TRANG

## Backend (đã có, đã chạy thật)

**34 E2E test, 4 suite, PASS ổn định qua nhiều lần chạy liên tiếp** — chạy bằng Jest + Supertest
trên 1 Nest app thật (không mock HTTP layer), nói chuyện với PostgreSQL thật
(`viec_nha_trang_test`, tách biệt hoàn toàn dev/production — `test/global-setup.ts` chủ động từ
chối chạy nếu `DATABASE_URL` không chứa `_test`).

```bash
cd apps/backend && npm run test:e2e
```

| Suite | File | Bao phủ |
|---|---|---|
| Job seeker flow | `test/job-seeker.e2e-spec.ts` | Register/login OTP → profile → search → filter → detail → save/unsave → apply → track status (§48 seeker flow) |
| Employer flow | `test/employer.e2e-spec.ts` | Login → role switch → business profile → location → post job (+ reject thiếu lương) → list mine → nhận applicant → toàn bộ state machine NEW→VIEWED→CONTACTED→INTERVIEW→HIRED → close (§48 employer flow) |
| Admin flow | `test/admin.e2e-spec.ts` | Login → dashboard → list users/employers/jobs/applications/reports → category/area CRUD (§48 admin flow) |
| Security | `test/security.e2e-spec.ts` | 401 vs 403, forged JWT, cross-tenant ownership (job/applicant/status) với xác nhận dữ liệu **không đổi** sau 403, duplicate apply, input validation, SQL injection payload, passwordHash không leak |

Chi tiết đầy đủ + các bug tìm được qua E2E thật (không phải chỉ compile): `docs/PHASE2-REPORT.md`.

## Backend — chưa có (trung thực)

- **Unit test** (`npm run test`, Jest, không cần DB) — script tồn tại trong `package.json` từ
  Phase 1 nhưng chưa có file `*.spec.ts` nào trong `src/`. E2E test hiện tại bao phủ đủ các
  luồng nghiệp vụ chính nên ưu tiên thấp hơn; unit test có giá trị nhất cho logic thuần túy như
  `MatchScoreService.computeScore` (không cần DB, dễ test nhiều case biên) — ứng viên tốt nếu
  bổ sung sau.
- **"Security rules test"** theo nghĩa Firestore không áp dụng (không dùng Firestore) — tương
  đương của nó trong kiến trúc này chính là suite `security.e2e-spec.ts` đã có.

## Admin CMS (Next.js)

Không có test tự động — xác minh bằng `npm run build` (typecheck + compile, đã PASS nhiều lần
qua các phase). Không có E2E UI test (Playwright/Cypress) — admin CMS gọi cùng REST API đã được
E2E test ở backend, rủi ro chính còn lại là UI-only bug không thể bắt được bởi test backend.

## Mobile (Flutter)

**Chưa test được trong bất kỳ phase nào của repo này** — Flutter SDK không có trong môi trường
làm việc (`flutter: command not found`, xác nhận lại ở Phase 2 và phase này). Code được viết
theo đúng convention Flutter nhưng **chưa qua** `flutter pub get`, `flutter analyze`,
`dart format --set-exit-if-changed .`, hay bất kỳ widget/integration test nào. Đây là rủi ro lớn
nhất về chất lượng trong toàn bộ repo — không nên coi mobile app "hoạt động" cho tới khi việc
này được làm trong môi trường có Flutter SDK.

## Load testing

Không phải correctness test, nhưng liên quan: xem `docs/LOAD_TESTING.md` — script k6 thật, đã
chạy smoke test thật (10-20 VU) trên máy dev, chưa chạy ở quy mô target (100-5000 VU) vì cần
môi trường Cloud Run/Cloud SQL thật.

## Nguyên tắc (§56 master prompt — Definition of Done)

Một chức năng chỉ coi là xong khi: code chạy thật + UI hoạt động + backend hoạt động + database
hoạt động + có error handling + có validation + có test + docs cập nhật đúng thực tế + không có
secret + không phá chức năng khác. "Compile được" không phải là hoàn thành — nguyên tắc này đã
áp dụng xuyên suốt Phase 2 (tìm ra 4 bug thật qua chạy E2E thật, không phải qua đọc code) và
phase này (chạy k6 thật, build Docker thật dù bị chặn bởi network sandbox, không giả vờ).
