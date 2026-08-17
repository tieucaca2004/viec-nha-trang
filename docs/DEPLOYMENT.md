# DEPLOYMENT — Cloud Run + Cloud SQL

Quyết định kiến trúc: xem `docs/PLAN.md` §0-1. Không thuê VPS; backend là 1 container stateless
chạy trên Cloud Run, database là Cloud SQL PostgreSQL managed.

## Trạng thái đã kiểm chứng trong môi trường làm việc này

- `Dockerfile` (multi-stage: build → runtime) đã viết, cú pháp hợp lệ (Docker parse OK, dừng
  đúng ở bước pull base image).
- **Không build được image thật ở đây** — `docker build` báo `403 Forbidden` khi tải
  `node:20-slim` từ registry, cùng nguyên nhân với việc không pull được `postgres:16-alpine` ở
  Phase 2 (chính sách mạng của sandbox này, không phải lỗi Dockerfile). Từng lệnh bên trong
  Dockerfile (`npm ci`, `npm run build`, `npm ci --omit=dev`, `prisma generate`) đã được chạy
  và xác nhận thành công riêng lẻ nhiều lần trong các phase trước — chỉ riêng bước "đóng gói
  vào image Docker" chưa chạy được ở đây.
- **Chưa có GCP project/Cloud Run/Cloud SQL thật** được deploy trong phiên làm việc này — mọi
  hướng dẫn dưới đây là quy trình chuẩn, cần một người có quyền truy cập GCP console/`gcloud`
  CLI để thực thi và xác nhận.

## 1. Chuẩn bị Cloud SQL

```bash
gcloud sql instances create viec-nha-trang-db \
  --database-version=POSTGRES_16 \
  --tier=db-custom-1-3840 \
  --region=asia-southeast1 \
  --storage-auto-increase \
  --backup-start-time=03:00

gcloud sql databases create viec_nha_trang --instance=viec-nha-trang-db

gcloud sql users set-password postgres --instance=viec-nha-trang-db --password=<mật khẩu mạnh, lưu Secret Manager>
```

Không mở public IP. Cloud Run kết nối qua Cloud SQL Auth Proxy (Unix socket) — Cloud Run tự động
mount socket này khi gắn `--add-cloudsql-instances`, không cần VPC connector riêng cho MVP.

`DATABASE_URL` khi đó có dạng:

```
postgresql://postgres:<password>@localhost/viec_nha_trang?host=/cloudsql/<project>:<region>:viec-nha-trang-db&connection_limit=5
```

`connection_limit` nên đặt thấp (5-10) vì mỗi Cloud Run instance mở connection riêng — nhiều
instance × connection_limit cao dễ chạm giới hạn max_connections của tier Cloud SQL nhỏ (xem
`docs/SCALABILITY.md`).

## 2. Secret Manager

```bash
echo -n "<jwt access secret thật>" | gcloud secrets create viec-nha-trang-jwt-access --data-file=-
echo -n "<jwt refresh secret thật>" | gcloud secrets create viec-nha-trang-jwt-refresh --data-file=-
gcloud secrets create viec-nha-trang-fcm-service-account --data-file=./service-account.json
```

Không commit `service-account.json` vào repo — chỉ dùng để tạo secret rồi xóa khỏi máy local.

## 3. Migration trước khi deploy revision mới

**Không chạy `prisma migrate deploy` trong container startup** — nhiều Cloud Run instance có
thể khởi động song song, chạy migration đồng thời từ nhiều instance là rủi ro không cần thiết.
Thay vào đó chạy migration như 1 bước riêng, trước khi deploy:

```bash
# Từ máy có quyền truy cập Cloud SQL (hoặc 1 Cloud Build step / Cloud Run Job riêng):
DATABASE_URL="<cùng connection string, qua Cloud SQL Auth Proxy chạy local>" \
  npx prisma migrate deploy
```

## 4. Build & deploy

```bash
gcloud builds submit --tag asia-southeast1-docker.pkg.dev/<project>/viec-nha-trang/backend:latest apps/backend

gcloud run deploy viec-nha-trang-backend \
  --image asia-southeast1-docker.pkg.dev/<project>/viec-nha-trang/backend:latest \
  --region asia-southeast1 \
  --add-cloudsql-instances <project>:<region>:viec-nha-trang-db \
  --set-env-vars NODE_ENV=production \
  --set-secrets DATABASE_URL=viec-nha-trang-db-url:latest,JWT_ACCESS_SECRET=viec-nha-trang-jwt-access:latest,JWT_REFRESH_SECRET=viec-nha-trang-jwt-refresh:latest,FCM_SERVICE_ACCOUNT_JSON=viec-nha-trang-fcm-service-account:latest \
  --min-instances 0 \
  --max-instances 10 \
  --memory 512Mi \
  --cpu 1 \
  --allow-unauthenticated
```

- `--min-instances 0`: scale-to-zero khi không có traffic → chi phí gần 0 lúc rảnh (mục tiêu
  §37/§7 gốc, kiểm soát chi phí khi user còn ít).
- `--max-instances 10`: chặn chi phí bùng nổ nếu có traffic bất thường/tấn công — tăng dần theo
  traffic thật, không đặt "unlimited" ngay từ đầu.
- `--allow-unauthenticated`: API public (mobile app gọi trực tiếp, tự bảo vệ bằng JWT + rate
  limit ở tầng application, không phải bằng IAM của Cloud Run).

## 5. Admin CMS (Next.js)

Có thể deploy cùng cách (Cloud Run) hoặc bất kỳ hosting Next.js nào hỗ trợ static+API routes.
Không cần Cloud SQL access trực tiếp — admin CMS chỉ gọi REST API của backend qua
`NEXT_PUBLIC_API_BASE_URL`.

## 6. Rollback

Cloud Run giữ lịch sử revision — rollback là chuyển traffic 100% về revision trước:

```bash
gcloud run services update-traffic viec-nha-trang-backend --to-revisions=<revision cũ>=100
```

Rollback database: xem `docs/SCALABILITY.md`/backup strategy — Cloud SQL tự động backup hàng
ngày (đã bật `--backup-start-time` ở bước 1), point-in-time recovery khả dụng nếu bật binary
logging khi tạo instance.

## 7. Monitoring sau khi deploy

Cloud Run tự động xuất log (Cloud Logging) và metric (Cloud Monitoring: request count, latency,
CPU/memory, instance count) — không cần cài thêm agent. Thiết lập alert cơ bản:

```bash
gcloud alpha monitoring policies create --notification-channels=<channel> \
  --display-name="Cloud Run 5xx rate cao" \
  --condition-display-name="5xx > 5%" \
  ...
```

(Chi tiết policy cần cấu hình qua Console hoặc Terraform khi có project thật — không viết giả
policy YAML đầy đủ ở đây vì chưa verify được với project thật.)
