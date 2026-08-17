# SCALABILITY — VIỆC NHA TRANG

Mục tiêu (§5/§51 master prompt): phục vụ tối thiểu 50.000 registered users, 10.000+ DAU, hàng
trăm concurrent user, mà không phải viết lại kiến trúc — và có đường mở rộng lên 100k/500k.

## Nguyên tắc nền tảng đã áp dụng (không phải lý thuyết — đã có trong code)

| Nguyên tắc | Đã làm ở đâu |
|---|---|
| Backend stateless | JWT stateless (không session server-side); refresh token chỉ lưu hash để revoke, không phải session state bắt buộc mọi request phải đọc |
| Mỗi entity 1 row riêng, không phải 1 document khổng lồ | Mỗi job/application/notification là 1 row trong bảng riêng (`docs/DATABASE.md`) |
| Không global counter bị tranh ghi | Counter (`viewCount`, `applicationCount`...) nằm trên chính row `jobs`, tăng bằng `UPDATE ... SET x = x+1`, khóa row-level (Postgres MVCC), không khóa bảng, không có 1 document tổng bị hàng nghìn client ghi |
| Pagination bắt buộc | `JobsService.findMany` có `limit`/`offset` (mặc định 20, tối đa 50) từ Phase 1, không đổi |
| Không tải toàn bộ collection | Không có endpoint nào trả toàn bộ `jobs`/`applications` không giới hạn |
| Index khớp truy vấn thật | `[areaId,status]`, `[categoryId,status]`, `[employerId]` trên `jobs`; `[jobSeekerId]`, `[jobId,status]` trên `applications`; `[userId,readAt]` trên `notifications` |
| Unique constraint chặn spam ở tầng DB | `(jobId,jobSeekerId)` trên `applications`, `(userId,jobId)` trên `saved_jobs` — không chỉ chặn ở service layer |
| Rate limiting | `@nestjs/throttler` toàn cục + riêng cho OTP |

## Kế hoạch mở rộng theo tầng

### Compute (Cloud Run)
- Autoscale theo request đến, `min-instances=0` lúc traffic thấp, tăng `max-instances` khi có
  số liệu traffic thật (xem `docs/DEPLOYMENT.md` §4). Mỗi instance stateless — scale ngang tự
  do, không cần sticky session.
- CPU/memory bắt đầu nhỏ (512Mi/1 vCPU), tăng nếu profiling cho thấy cần (chưa có số liệu thật
  để quyết định trước — không over-provision khi chưa biết traffic thật).

### Database (Cloud SQL PostgreSQL)
- **Connection pooling là rủi ro lớn nhất khi scale ngang Cloud Run** — mỗi instance mở
  connection riêng tới Postgres, N instance × M connection/instance dễ vượt
  `max_connections` của tier nhỏ. Giải pháp theo thứ tự ưu tiên khi traffic tăng:
  1. Giới hạn `connection_limit` trong `DATABASE_URL` (Prisma) ở mức thấp (5-10) mỗi instance.
  2. Bật **Cloud SQL connection pooling** (PgBouncer built-in, GA trên Cloud SQL) khi số Cloud
     Run instance đồng thời tăng cao.
  3. Nâng tier Cloud SQL (`db-custom-1-3840` → cao hơn) khi CPU/memory của DB là bottleneck
     thật (đo qua Cloud Monitoring, không đoán).
- **Read replica**: khi tỷ lệ đọc/ghi lệch hẳn về đọc (tìm kiếm job >> đăng job), có thể tách
  route GET sang read replica. Chưa cần ở quy mô 50k user — index đã đủ tốt cho truy vấn hiện
  tại; đây là bước tiếp theo khi có số liệu P95/P99 thật vượt ngưỡng chấp nhận được (xem
  `docs/LOAD_TESTING.md`).
- **Denormalization đã có sẵn ở mức hợp lý**: `applicationCount`/`viewCount`... lưu ngay trên
  `jobs` thay vì `COUNT()` mỗi lần load list — tránh N+1 aggregate query trên trang chủ.

### Cache
- Chưa cần cache lớp ứng dụng ở quy mô hiện tại: `categories` (15 dòng), `areas` (17 dòng) gần
  như tĩnh, đọc trực tiếp từ Postgres đã đủ nhanh (đọc theo index, dataset nhỏ). Khi traffic
  cao hơn nhiều, các endpoint này là ứng viên cache đầu tiên (in-memory LRU hoặc Redis) vì đọc
  nhiều, ghi cực hiếm (chỉ admin sửa).
- Job search/filter **không cache mặc định** vì kết quả phụ thuộc vị trí/bộ lọc gần như duy
  nhất mỗi request — cache ở đây dễ trả dữ liệu cũ (job đã đóng) hơn là tiết kiệm được nhiều.

### Notification/push
- Ghi DB đồng bộ, gửi push bất đồng bộ theo kiểu "best-effort, không chặn luồng chính" (đã
  implement: lỗi gửi push bị catch và log, không làm fail request tạo application/đổi trạng
  thái). Khi khối lượng notification tăng cao (hàng chục nghìn/phút), bước tiếp theo là tách
  việc gửi push ra một queue (Cloud Tasks) thay vì gọi trực tiếp trong request — **chưa cần ở
  MVP**, ghi vào `docs/ROADMAP.md` nếu số liệu thật cho thấy cần.

### Object storage (ảnh)
- Google Cloud Storage, không phải lưu ảnh trong Postgres. Nén ảnh phía client trước khi upload
  (mobile) — đã ghi vào `docs/ROADMAP.md` là việc mobile chưa làm (cần Flutter SDK để build).

## Con đường 50k → 100k → 500k user (không phải viết lại)

| Mốc | Thay đổi cần thiết | KHÔNG cần thay đổi |
|---|---|---|
| 50k users, 10k DAU | Tier Cloud SQL nhỏ, Cloud Run `max-instances` thấp | Kiến trúc, schema, API |
| 100k users | Bật Cloud SQL connection pooling, tăng `max-instances` | Schema, API, mobile app |
| 500k users | Read replica cho truy vấn đọc, cân nhắc cache lớp ứng dụng cho categories/areas, tăng tier Cloud SQL | Không đổi framework, không đổi từ Postgres sang hệ khác |

Ranh giới rõ ràng theo §51: Mobile / API-backend / Database / Storage / Notification / Analytics
/ Admin / Payment đã tách module độc lập từ Phase 1 (`apps/backend/src/<domain>`), không có
module nào phụ thuộc chặt vào module khác ngoài qua service interface — cho phép tách thành
service riêng sau này nếu thật sự cần (chưa cần ở MVP, tránh over-engineering theo §57).

## Giới hạn trung thực

Chưa có số liệu load test thật (xem `docs/LOAD_TESTING.md`) để xác nhận các ngưỡng trên bằng
đo lường thực tế thay vì suy luận từ thiết kế. Chiến lược này dựa trên nguyên tắc kiến trúc đã
biết hoạt động tốt với Postgres ở quy mô tương tự, không phải benchmark đã chạy trong repo này.
