# LOAD TESTING — VIỆC NHA TRANG

Script thật, chạy được: [`apps/backend/loadtest/scenarios.js`](../apps/backend/loadtest/scenarios.js)
(k6). Bao phủ đúng 8/10 kịch bản yêu cầu ở §6 master prompt trong 1 script duy nhất (weighted
random per iteration, gần với hành vi thật: đọc nhiều hơn ghi):

1. Search jobs
2. Filter jobs
3. Open job detail
4. Apply to job
5. Save job
6. Employer creates job
7. Employer reads applicants
8. Notifications

(Login đã được đo trong `setup()` qua `otp verify` check. Update application status chưa có
kịch bản riêng trong script - ghi vào phần "Còn thiếu" bên dưới, không giả vờ đã có.)

## Cách chạy

```bash
cd apps/backend
npm run start:dev   # hoặc chạy image Cloud Run thật, xem docs/DEPLOYMENT.md

# Môi trường target PHẢI có:
#   SMS_PROVIDER=console         (để dùng route debug OTP)
#   NODE_ENV != production        (route debug OTP tự trả 404 nếu NODE_ENV=production)
#   OTP_REQUEST_THROTTLE_LIMIT / OTP_VERIFY_THROTTLE_LIMIT đặt cao (setup() gọi OTP dồn dập)
#   THROTTLE_LIMIT đặt đủ cao NẾU chạy k6 từ 1 máy/1 IP duy nhất (xem "Phát hiện quan trọng" dưới)

k6 run -e BASE_URL=http://localhost:3000/api/v1 -e VUS=100 -e DURATION=2m loadtest/scenarios.js
```

`-e VUS=` / `-e DURATION=` tương ứng TEST A/B/C/D của §49 master prompt (100/500/1000 concurrent
users, pattern 5000 request). `-e SEEKER_POOL_SIZE=` số tài khoản ứng viên dùng chung trong pool
(mặc định 20) - tăng lên nếu muốn mô phỏng nhiều danh tính khác nhau hơn.

## Route debug OTP — chỉ tồn tại ngoài production

`GET /auth/otp/debug/:phone` cho phép load test tool lấy mã OTP vừa gửi mà không cần đọc log
server (không có cách khác để 100-5000 VU tự động đăng nhập qua OTP thật). Route này:

- Trả `404` ngay lập tức nếu `NODE_ENV === 'production'`.
- Trả `404` nếu SMS provider đang cấu hình không phải `ConsoleSmsProvider` (nghĩa là production
  đã chuyển sang gửi SMS thật, không còn lưu mã trong bộ nhớ để trả về).
- Không đọc được OTP của **người dùng thật** trong bất kỳ trường hợp nào — chỉ đọc được mã vừa
  được `ConsoleSmsProvider` "gửi" (tức là log ra console) trong chính tiến trình đang chạy.

Xem `docs/SECURITY.md` để biết rõ giới hạn của route này.

## Kết quả đã chạy thật trong môi trường này (KHÔNG phải ước tính)

Chạy trên: backend `nest start --watch` (không phải Cloud Run — dev machine của sandbox này),
PostgreSQL 16 local (không phải Cloud SQL), **1 máy, 1 IP nguồn duy nhất**.

### Lần 1 — 10 VUs, 15s, throttle mặc định (`THROTTLE_LIMIT=60`)

```
checks.........................: 65.16% 232 out of 356
http_req_failed.................: 32.63% 124 out of 380
http_req_duration...............: avg=8.17ms  p(95)=16.43ms
```

**Phát hiện quan trọng**: tỷ lệ lỗi cao **không phải do backend chậm hay lỗi logic** — search/
filter bị `429 Too Many Requests` vì tất cả traffic của k6 đến từ **cùng 1 IP**, chạm giới hạn
`ThrottlerModule` toàn cục (`THROTTLE_LIMIT=60`/phút/IP) vốn được thiết kế cho 1 người dùng thật,
không phải để chịu hàng trăm request/giây dồn từ 1 nguồn. Đây là hành vi **đúng thiết kế** của
rate limiter, nhưng có nghĩa: **load test single-IP sẽ luôn đụng trần rate limit trước khi đo
được khả năng chịu tải thật của DB/backend** — phải tách 2 việc ra khi đọc kết quả.

### Lần 2 — 20 VUs, 20s, `THROTTLE_LIMIT=5000` (chỉ để cô lập rate-limit khỏi phép đo)

```
checks.........................: 100.00% 819 out of 819
http_req_failed.................: 0.00%   0 out of 852
http_req_duration...............: avg=9.4ms  p(90)=10.31ms  p(95)=12.25ms
http_reqs.......................: 852 requests, 10.24 req/s
```

0% lỗi, P95 = 12ms — xa dưới ngưỡng threshold đặt trong script (`p(95)<800ms`). Ở quy mô nhỏ
(20 VU, máy dev + Postgres local), backend và DB không phải bottleneck.

### Những gì 2 lần chạy này CHỨNG MINH được

- Script chạy thật, đo thật, không phải giả định lý thuyết.
- Ứng dụng logic đúng dưới tải đồng thời nhỏ (không lỗi 500, không deadlock, không application
  bị duplicate — unique constraint đã test riêng ở Phase 2).
- **Rate limiter hoạt động đúng như thiết kế** — đây tự nó là một xác nhận tích cực cho §7 (cost
  control/anti-spam), dù nó làm phức tạp việc đọc kết quả load test single-IP.

### Những gì 2 lần chạy này KHÔNG chứng minh được (trung thực, không phóng đại)

- **Chưa chạy ở quy mô 100/500/1.000/5.000 concurrent thật** như §6/§49 yêu cầu — môi trường
  này là 1 máy chia sẻ tài nguyên cho cả backend + Postgres + k6 cùng lúc, không phản ánh
  Cloud Run + Cloud SQL thật. Chạy ở quy mô đó cần:
  1. Deploy backend thật lên Cloud Run + Cloud SQL (xem `docs/DEPLOYMENT.md`).
  2. Chạy k6 từ nhiều nguồn (k6 Cloud, hoặc nhiều VM) để tránh chính k6/network của máy chạy
     test trở thành bottleneck giả trước khi backend thật bị stress.
  3. Cấu hình `THROTTLE_LIMIT` của môi trường load test cao hơn traffic dự kiến từ **nhiều IP
     thật** (khác với single-IP synthetic test) - hoặc phân tích riêng theo IP nếu k6 chạy đa
     nguồn thật.
- **Chưa đo Firestore reads/writes** (không áp dụng — dùng Postgres, xem `docs/DATABASE.md`).
- **Chưa đo Cloud Run cost/CPU/memory thật** — cần instance Cloud Run thật đang chạy.

## Còn thiếu (ghi nhận, không tự làm thêm ngoài phạm vi)

- Kịch bản "Update application status" chưa có trong `scenarios.js` — cần 1 job seeker apply
  trước rồi employer đổi trạng thái application đó, phức tạp hơn trong mô hình VU độc lập của
  k6 (mỗi iteration không biết application nào vừa được tạo bởi VU khác). Có thể thêm bằng cách
  cho employer tự truy vấn danh sách applicant của job và đổi trạng thái của 1 applicant ngẫu
  nhiên trong đó — để trong `docs/ROADMAP.md`.
- Chưa chạy test ở quy mô 100-5000 VU thật (xem trên) — cần môi trường Cloud Run/Cloud SQL thật.
