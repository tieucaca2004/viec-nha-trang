import { PrismaClient } from '@prisma/client';

/**
 * Chạy 1 lần trước toàn bộ e2e suite: dọn sạch DB test (KHÔNG phải DB development/production -
 * DATABASE_URL lúc này đã được dotenv-cli trỏ vào .env.test, xem package.json script "test:e2e").
 */
export default async function globalSetup() {
  if (!process.env.DATABASE_URL?.includes('_test')) {
    throw new Error(
      `Refusing to run e2e global-setup: DATABASE_URL does not look like a test database (${process.env.DATABASE_URL}).`,
    );
  }

  const prisma = new PrismaClient();
  const tables: { tablename: string }[] = await prisma.$queryRaw`
    SELECT tablename FROM pg_tables WHERE schemaname = 'public' AND tablename != '_prisma_migrations'
  `;
  if (tables.length > 0) {
    const names = tables.map((t) => `"public"."${t.tablename}"`).join(', ');
    await prisma.$executeRawUnsafe(`TRUNCATE TABLE ${names} RESTART IDENTITY CASCADE;`);
  }
  await prisma.$disconnect();
}
