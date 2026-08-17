# COST — VIỆC NHA TRANG

Ước tính chi phí (§7/§37 master prompt), dựa trên kiến trúc thật đã chọn (Cloud Run + Cloud SQL
+ FCM, không phải Firestore/Firebase Auth). Giá tham khảo asia-southeast1 (Singapore, gần Việt
Nam nhất trong các region Google Cloud), làm tròn, **ước tính** — không phải hóa đơn thật vì
chưa có project GCP nào đang chạy.

## Cấu phần chi phí

| Dịch vụ | Free tier / mô hình giá | Ghi chú |
|---|---|---|
| Cloud Run | 2 triệu request/tháng miễn phí, sau đó ~$0.40/triệu request + CPU/memory theo giây thực tế dùng | `min-instances=0` → không tính phí lúc rảnh |
| Cloud SQL (db-custom-1-3840) | Không có free tier, ~$50-70/tháng chạy 24/7 (1 vCPU, 3.75GB RAM, region asia-southeast1) | Chi phí cố định lớn nhất ở quy mô nhỏ — không scale-to-zero được (database luôn phải chạy) |
| Cloud SQL storage | ~$0.17/GB/tháng (SSD) | Nhỏ ở quy mô 50k user (ước tính vài GB) |
| Cloud SQL backup | ~$0.08/GB/tháng | Tự động, đã bật ở `docs/DEPLOYMENT.md` §1 |
| Firebase Cloud Messaging | Miễn phí, không giới hạn | Google không tính phí gửi push |
| Google Cloud Storage (ảnh) | ~$0.02/GB/tháng lưu trữ + egress | Cần compress ảnh phía client (mobile — chưa làm, xem ROADMAP) để giữ chi phí thấp |
| Cloud Logging/Monitoring | 50GB log/tháng miễn phí | Đủ cho quy mô MVP, không cần cấu hình thêm |
| Secret Manager | 6 secret active + 10.000 lượt truy cập/tháng miễn phí | Đủ dùng, số secret của app này rất ít |

## Ước tính theo mốc người dùng

Giả định: mỗi DAU trung bình gọi ~15-20 request/ngày (mở app, xem vài job, có thể ứng tuyển).

| Mốc | DAU ước tính | Request/tháng ước tính | Cloud Run | Cloud SQL | Tổng ước tính/tháng |
|---|---|---|---|---|---|
| Ra mắt (1k user) | ~300 | ~150.000 | Miễn phí (trong free tier) | ~$50-70 (tier nhỏ nhất) | **~$50-70** |
| 10k user (mục tiêu §5) | ~2.000-3.000 | ~1.5 triệu | Gần free tier, có thể vượt nhẹ | ~$50-70 (chưa cần nâng tier) | **~$60-90** |
| 50k user (mục tiêu §5) | ~10.000+ | ~6 triệu | ~$20-40 (vượt free tier) | ~$100-150 (cần nâng tier để chịu tải + connection pooling) | **~$150-250** |

Cột "Cloud SQL" là cấu phần chiếm phần lớn chi phí ở quy mô nhỏ vì **database không scale-to-
zero được** như Cloud Run — đây là đánh đổi đã chấp nhận khi giữ Postgres thay vì Firestore (xem
`docs/PLAN.md` §0): Firestore tính theo lượt đọc/ghi thực tế (có thể rẻ hơn ở quy mô rất nhỏ,
nhưng dễ đắt đột biến nếu query pattern sai — đã thấy trong nhiều case study thực tế mà §32 gốc
cảnh báo tránh hotspot). Cloud SQL có chi phí sàn cố định nhưng **dễ dự đoán và kiểm soát hơn**.

## Nguyên tắc kiểm soát chi phí đã áp dụng trong code (không chỉ lý thuyết)

| Nguyên tắc (§7/§37 master prompt) | Đã làm ở đâu |
|---|---|
| Pagination mọi danh sách lớn | `JobsService.findMany` limit/offset (Phase 1, không đổi) |
| Không polling liên tục | REST, không dùng long-polling; mobile app tải lại theo pull-to-refresh, không interval timer |
| Không có realtime listener không cần thiết | Không dùng Firestore realtime listener (không áp dụng vì đổi sang Postgres) — notification là REST GET theo yêu cầu người dùng, không phải WebSocket/SSE luôn mở |
| Query giới hạn, index đúng | `docs/DATABASE.md`/`docs/SCALABILITY.md` |
| Rate limiting chống spam | `@nestjs/throttler`, đặc biệt route OTP — chặn cả spam lẫn chi phí compute do request rác |
| Compress ảnh trước upload | **Chưa làm ở mobile** (cần Flutter SDK để build/test, xem ROADMAP) — đây là rủi ro chi phí egress/storage thật nếu không làm trước khi launch |

## Budget alert (chưa cấu hình — cần project GCP thật)

```bash
gcloud billing budgets create \
  --billing-account=<billing account id> \
  --display-name="Việc Nha Trang - monthly budget" \
  --budget-amount=200USD \
  --threshold-rule=percent=50 \
  --threshold-rule=percent=90 \
  --threshold-rule=percent=100
```

Chưa chạy được lệnh này trong môi trường làm việc — cần billing account thật. Ghi lại quy trình
để người có quyền truy cập GCP console thực hiện trước khi launch, không phải sau.

## Giới hạn trung thực

Đây là ước tính dựa trên bảng giá công khai của Google Cloud và giả định hành vi người dùng hợp
lý, **không phải chi phí đã đo được thật** (chưa có project/traffic thật). Nên coi đây là baseline
để so sánh khi có hóa đơn thật đầu tiên, không phải cam kết chính xác.
