import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { AppModule } from '../../src/app.module';
import { PrismaService } from '../../src/prisma/prisma.service';
import { SMS_PROVIDER } from '../../src/common/services/tokens';
import { CapturingSmsProvider } from './capturing-sms.provider';

/**
 * Dựng app NestJS thật (cùng AppModule sản xuất dùng) chạy trên DATABASE_URL của .env.test.
 * Chỉ thay SMS provider (bắt OTP thay vì gửi SMS thật) - rate limit OTP vẫn active như
 * production, được nới ngưỡng qua OTP_REQUEST_THROTTLE_LIMIT/OTP_VERIFY_THROTTLE_LIMIT
 * trong .env.test (xem auth.controller.ts) vì nhiều test case gọi OTP liên tiếp từ cùng 1 IP.
 * Global pipes/prefix phải khớp main.ts để test phản ánh đúng hành vi thật.
 */
export async function buildTestApp(): Promise<{
  app: INestApplication;
  prisma: PrismaService;
  sms: CapturingSmsProvider;
}> {
  const moduleRef = await Test.createTestingModule({
    imports: [AppModule],
  })
    .overrideProvider(SMS_PROVIDER)
    .useClass(CapturingSmsProvider)
    .compile();

  const app = moduleRef.createNestApplication();
  app.setGlobalPrefix('api/v1');
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
  await app.init();

  const prisma = moduleRef.get(PrismaService);
  const sms = moduleRef.get(SMS_PROVIDER);

  return { app, prisma, sms };
}
