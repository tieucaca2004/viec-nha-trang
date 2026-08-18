#!/usr/bin/env bash
# Script chạy THỦ CÔNG trên server thật (KHÔNG chạy trong sandbox Claude Code) để lên staging
# VIỆC NHA TRANG. Hoàn toàn tách biệt project/network/volume - không đụng tới container nào khác
# (vd pshop-music/OpenClaw) - chỉ dùng docker compose -f docker-compose.staging.yml
# -p viec-nha-trang-staging cho MỌI lệnh, không có lệnh Docker phá huỷ/toàn cục nào.
#
# Trước khi chạy:
#   1. cp docker-compose.staging.env.example docker-compose.staging.env
#      rồi điền STAGING_DB_PASSWORD thật (vd `openssl rand -base64 32`).
#   2. cp apps/backend/.env.staging.example apps/backend/.env.staging
#      rồi điền JWT_ACCESS_SECRET/JWT_REFRESH_SECRET thật.
#   3. Sửa Caddyfile.staging: thay "staging-viecnhatrang.CHANGE-ME.example" bằng domain thật của
#      bạn, đã trỏ DNS A/AAAA về IP server này. Script sẽ TỪ CHỐI khởi động Caddy (public HTTPS)
#      nếu vẫn còn placeholder - postgres/backend vẫn lên được để bạn tự kiểm tra nội bộ trước.
#
# Chạy: ./deploy-staging.sh
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE_FILE="docker-compose.staging.yml"
ENV_FILE="docker-compose.staging.env"
PROJECT="viec-nha-trang-staging"
CADDY_PLACEHOLDER="staging-viecnhatrang.CHANGE-ME.example"

dc() {
  # Luôn dùng đúng file + project name này - không có biến thể nào khác trong script.
  docker compose -f "$COMPOSE_FILE" -p "$PROJECT" --env-file "$ENV_FILE" "$@"
}

if [ ! -f "$ENV_FILE" ]; then
  echo "LỖI: $ENV_FILE chưa tồn tại. Copy từ docker-compose.staging.env.example và điền STAGING_DB_PASSWORD thật trước." >&2
  exit 1
fi

if [ ! -f apps/backend/.env.staging ]; then
  echo "LỖI: apps/backend/.env.staging chưa tồn tại. Copy từ apps/backend/.env.staging.example và điền JWT secret thật trước." >&2
  exit 1
fi

if grep -q "CHANGE-ME" "$ENV_FILE"; then
  echo "LỖI: $ENV_FILE vẫn còn giá trị CHANGE-ME - điền mật khẩu DB thật trước khi chạy." >&2
  exit 1
fi

if grep -q "CHANGE-ME" apps/backend/.env.staging; then
  echo "LỖI: apps/backend/.env.staging vẫn còn giá trị CHANGE-ME - điền JWT secret thật trước khi chạy." >&2
  exit 1
fi

echo "==> [1/7] Khởi động PostgreSQL"
dc up -d postgres

echo "==> [2/7] Chờ PostgreSQL healthy"
for i in $(seq 1 30); do
  status="$(docker inspect -f '{{.State.Health.Status}}' viec-nha-trang-staging-postgres 2>/dev/null || echo "starting")"
  if [ "$status" = "healthy" ]; then
    echo "    postgres: healthy"
    break
  fi
  if [ "$i" -eq 30 ]; then
    echo "LỖI: postgres không healthy sau 30 lần thử. Xem: docker compose -f $COMPOSE_FILE -p $PROJECT logs postgres" >&2
    exit 1
  fi
  sleep 2
done

echo "==> [3/7] Build và khởi động backend"
dc up -d --build backend

echo "==> [4/7] Chạy Prisma migration thật (không migrate dev, không reset data)"
dc exec -T backend npx prisma migrate deploy

echo "==> [5/7] Kiểm tra health backend nội bộ (Node 20 fetch có sẵn, không phụ thuộc wget/curl)"
for i in $(seq 1 15); do
  if dc exec -T backend node -e "
    fetch('http://localhost:3000/api/v1/health')
      .then(async (r) => { if (!r.ok) throw new Error('HTTP ' + r.status); console.log(await r.text()); process.exit(0); })
      .catch((e) => { console.error(String(e)); process.exit(1); });
  "; then
    echo "    backend: health OK"
    break
  fi
  if [ "$i" -eq 15 ]; then
    echo "LỖI: backend health check thất bại sau 15 lần thử. Xem: docker compose -f $COMPOSE_FILE -p $PROJECT logs backend" >&2
    exit 1
  fi
  sleep 2
done

echo "==> [6/7] Kiểm tra domain Caddy trước khi mở HTTPS công khai"
if grep -q "$CADDY_PLACEHOLDER" Caddyfile.staging; then
  echo "    Caddyfile.staging vẫn dùng domain placeholder ($CADDY_PLACEHOLDER)."
  echo "    KHÔNG khởi động Caddy - postgres + backend đã chạy, kiểm tra nội bộ xong."
  echo "    Sửa Caddyfile.staging với domain thật rồi chạy lại script này để bật Caddy."
else
  echo "    Domain thật đã cấu hình - khởi động Caddy"
  dc up -d caddy
fi

echo "==> [7/7] Trạng thái toàn bộ container staging"
dc ps

echo "==> Xong. Nếu Caddy đã bật: xác nhận DNS domain trỏ đúng IP server rồi mới mở port 80/443 trên router."
