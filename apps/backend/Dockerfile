# Multi-stage build cho Cloud Run (đặc tả docs/PLAN.md §1-2: không VPS, autoscale, stateless).
# Image cuối chỉ chứa production dependencies + code đã build - không có devDependencies,
# không có source TypeScript, không có test.

FROM node:20-bookworm-slim AS builder
WORKDIR /app

COPY package*.json ./
COPY prisma ./prisma
RUN npm ci

COPY tsconfig.json nest-cli.json ./
COPY src ./src
RUN npm run build

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

# Cloud Run cấp PORT qua biến môi trường runtime - main.ts đã đọc process.env.PORT sẵn.
EXPOSE 3000
USER node
CMD ["node", "dist/main.js"]
