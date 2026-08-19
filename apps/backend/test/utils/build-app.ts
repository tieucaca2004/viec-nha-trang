import { INestApplication, ValidationPipe } from '@nestjs/common';
import { Test } from '@nestjs/testing';
import { AppModule } from '../../src/app.module';
import { PrismaService } from '../../src/prisma/prisma.service';
import { SMS_PROVIDER, EMAIL_PROVIDER } from '../../src/common/services/tokens';
import { CapturingSmsProvider } from './capturing-sms.provider';
import { CapturingEmailProvider } from './capturing-email.provider';

/**
 * Dựng app NestJS thật (cùng AppModule sản xuất dùng) chạy trên DATABASE_URL của .env.test.
 * Chỉ thay SMS/Email provider (bắt OTP/mã xác minh thay vì gửi thật) - rate limit vẫn active như
 * production, được nới ngưỡng qua các biến OTP_..._THROTTLE_LIMIT và EMAIL_VERIFICATION_..._THROTTLE_LIMIT
 * trong .env.test (xem auth.controller.ts) vì nhiều test case gọi liên tiếp từ cùng 1 IP.
 * Global pipes/prefix phải khớp main.ts để test phản ánh đúng hành vi thật.
 */
export async function buildTestApp(): Promise<{
  app: INestApplication;
  prisma: PrismaService;
  sms: CapturingSmsProvider;
  email: CapturingEmailProvider;
}> {
  const moduleRef = await Test.createTestingModule({
    imports: [AppModule],
  })
    .overrideProvider(SMS_PROVIDER)
    .useClass(CapturingSmsProvider)
    .overrideProvider(EMAIL_PROVIDER)
    .useClass(CapturingEmailProvider)
    .compile();

  const app = moduleRef.createNestApplication();
  app.setGlobalPrefix('api/v1');
  app.useGlobalPipes(new ValidationPipe({ whitelist: true, forbidNonWhitelisted: true, transform: true }));
  await app.init();

  const prisma = moduleRef.get(PrismaService);
  const sms = moduleRef.get(SMS_PROVIDER);
  const email = moduleRef.get(EMAIL_PROVIDER);

  return { app, prisma, sms, email };
}
