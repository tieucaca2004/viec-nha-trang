# Multi-stage build cho Cloud Run (đặc tả docs/PLAN.md §1-2: không VPS, autoscale, stateless).
# Image cuối chỉ chứa production dependencies + code đã build - không có devDependencies,
# không có source TypeScript, không có test.

FROM node:20-slim AS builder
WORKDIR /app

COPY package*.json ./
COPY prisma ./prisma
RUN npm ci

COPY tsconfig.json nest-cli.json ./
COPY src ./src
RUN npm run build

FROM node:20-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production

COPY package*.json ./
COPY prisma ./prisma
RUN npm ci --omit=dev && npx prisma generate

COPY --from=builder /app/dist ./dist

# Cloud Run cấp PORT qua biến môi trường runtime - main.ts đã đọc process.env.PORT sẵn.
EXPOSE 3000
USER node
CMD ["node", "dist/main.js"]
