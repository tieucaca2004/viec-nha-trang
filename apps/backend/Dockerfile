# Multi-stage build cho Cloud Run (đặc tả docs/PLAN.md §1-2: không VPS, autoscale, stateless).
# Image cuối chỉ chứa production dependencies + code đã build - không có devDependencies,
# không có source TypeScript, không có test.

FROM node:20-bookworm-slim AS builder
WORKDIR /app

COPY package*.json ./
COPY prisma ./prisma
RUN npm ci

COPY tsconfig.json tsconfig.seed.json nest-cli.json ./
COPY src ./src
RUN npm run build

# Biên dịch prisma/seed.ts sang JS ngay ở builder stage (nơi ts-node/typescript - devDependencies
# - vẫn còn cài) - image runtime chỉ chạy `node dist-seed/seed.js` bằng plain Node, KHÔNG cần
# ts-node trong production. Sửa đúng nguyên nhân staging từng phải seed thủ công (`npm ci
# --omit=dev` ở stage runtime không có ts-node, nên `npx prisma db seed` throw "ts-node: not
# found") thay vì cài ts-node trực tiếp vào container đang chạy.
RUN npm run build:seed

FROM node:20-bookworm-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production

# Pin rõ base image tới Debian 12 "bookworm" (OpenSSL 3.0.x) thay vì tag nổi "node:20-slim" (có
# thể đổi codename Debian theo thời gian) - và cài `openssl` để `prisma generate` dò đúng version
# libssl thật của chính image này, khớp với `binaryTargets` khai báo trong prisma/schema.prisma
# ("native" + "debian-openssl-3.0.x"). Sửa lỗi thật trên server: Prisma trước đó sinh nhầm engine
# debian-openssl-1.1.x (openssl 1.1 không tồn tại trong Debian 12) vì image slim thiếu gói
# openssl nên không dò được version thật, PrismaService.onModuleInit() crash khi load engine.
RUN apt-get update && apt-get install -y --no-install-recommends openssl \
    && rm -rf /var/lib/apt/lists/*

COPY package*.json ./
COPY prisma ./prisma
RUN npm ci --omit=dev && npx prisma generate

COPY --from=builder /app/dist ./dist
COPY --from=builder /app/dist-seed ./dist-seed

# Cloud Run cấp PORT qua biến môi trường runtime - main.ts đã đọc process.env.PORT sẵn.
EXPOSE 3000
USER node
CMD ["node", "dist/main.js"]
