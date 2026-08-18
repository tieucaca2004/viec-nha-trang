#!/usr/bin/env bash
# Script chạy THỦ CÔNG trên server thật (KHÔNG chạy trong sandbox Claude Code) để lên staging
# VIỆC NHA TRANG. Hoàn toàn tách biệt project/network/volume - không đụng tới container nào khác.
#
# Trước khi chạy:
#   1. cp apps/backend/.env.staging.example apps/backend/.env.staging
#      rồi điền DATABASE_URL/JWT_ACCESS_SECRET/JWT_REFRESH_SECRET thật (vd `openssl rand -base64 48`)
#   2. Sửa Caddyfile.staging: thay "staging-viecnhatrang.CHANGE-ME.example" bằng domain thật của bạn,
#      đã trỏ DNS A/AAAA về IP server này.
#   3. Đặt STAGING_DB_PASSWORD (và tuỳ chọn STAGING_DB_USER/STAGING_DB_NAME) trong biến môi trường
#      shell hoặc file .env cùng cấp docker-compose.staging.yml - PHẢI khớp với DATABASE_URL ở bước 1.
#
# Chạy: ./deploy-staging.sh
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE_FILE="docker-compose.staging.yml"
PROJECT="viec-nha-trang-staging"

if [ ! -f apps/backend/.env.staging ]; then
  echo "LỖI: apps/backend/.env.staging chưa tồn tại. Copy từ .env.staging.example và điền secret thật trước." >&2
  exit 1
fi

if [ -z "${STAGING_DB_PASSWORD:-}" ]; then
  echo "LỖI: biến môi trường STAGING_DB_PASSWORD chưa được đặt (phải khớp mật khẩu trong DATABASE_URL của .env.staging)." >&2
  exit 1
fi

echo "==> Build và khởi động stack staging (project: $PROJECT)"
docker compose -f "$COMPOSE_FILE" -p "$PROJECT" up -d --build

echo "==> Chạy Prisma migration thật (không migrate dev, không reset data)"
docker compose -f "$COMPOSE_FILE" -p "$PROJECT" exec -T backend npx prisma migrate deploy

echo "==> Trạng thái container"
docker compose -f "$COMPOSE_FILE" -p "$PROJECT" ps

echo "==> Kiểm tra health nội bộ (trong network Docker, chưa qua Caddy/domain)"
docker compose -f "$COMPOSE_FILE" -p "$PROJECT" exec -T backend wget -qO- http://localhost:3000/api/v1/health || {
  echo "CẢNH BÁO: health check nội bộ thất bại - xem log: docker compose -f $COMPOSE_FILE -p $PROJECT logs backend" >&2
}

echo "==> Xong. Xác nhận DNS domain trong Caddyfile.staging đã trỏ đúng IP server rồi mới mở port 80/443 trên router."
