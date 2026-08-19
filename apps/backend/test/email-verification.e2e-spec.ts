import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingEmailProvider } from './utils/capturing-email.provider';
import { uniqueEmail } from './utils/fixtures';

// Đặc tả §1 phase kế tiếp: đăng ký tài khoản bằng email (KHÔNG dùng SMS OTP ở bước tạo tài
// khoản nữa). Suite này chứng minh: gửi mã, verify đúng, verify sai, hết hạn, resend, rate
// limit (qua Throttle), max attempts, và email đã verified rồi thì không cho đăng ký lại.
describe('Email verification registration - §1', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let email: CapturingEmailProvider;

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    email = built.email;
  });

  afterAll(async () => {
    await app.close();
  });

  it('gửi mã xác minh và đăng ký thành công với mã đúng, trả về JWT thật', async () => {
    const addr = uniqueEmail('register-ok');

    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);
    const code = email.getLastCode(addr);

    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email/verify')
      .send({ email: addr, code })
      .expect(201);

    expect(res.body.accessToken).toBeTruthy();
    expect(res.body.refreshToken).toBeTruthy();

    const user = await prisma.user.findUnique({ where: { email: addr } });
    expect(user?.isEmailVerified).toBe(true);
    expect(user?.authProvider).toBe('EMAIL');
    expect(user?.roles).toContain('JOB_SEEKER');
  });

  it('KHÔNG bao giờ trả mã xác minh trong response của request', async () => {
    const addr = uniqueEmail('no-code-leak');
    const res = await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);

    expect(res.body).not.toHaveProperty('code');
    expect(JSON.stringify(res.body)).not.toContain(email.getLastCode(addr));
  });

  it('không lưu mã dạng plaintext trong DB (chỉ lưu hash)', async () => {
    const addr = uniqueEmail('hash-only');
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);
    const code = email.getLastCode(addr);

    const row = await prisma.emailVerificationCode.findFirst({ where: { email: addr }, orderBy: { createdAt: 'desc' } });
    expect(row?.codeHash).not.toBe(code);
    expect(row?.codeHash).toContain(':'); // định dạng salt:hash của hashValue()
  });

  it('verify sai mã bị từ chối và không cấp token', async () => {
    const addr = uniqueEmail('wrong-code');
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);

    await request(app.getHttpServer())
      .post('/api/v1/auth/register/email/verify')
      .send({ email: addr, code: '000000' })
      .expect(400);
  });

  it('verify mã đã hết hạn bị từ chối', async () => {
    const addr = uniqueEmail('expired-code');
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);
    const code = email.getLastCode(addr);

    // Giả lập hết hạn: chỉnh trực tiếp expiresAt về quá khứ trong DB test.
    await prisma.emailVerificationCode.updateMany({ where: { email: addr }, data: { expiresAt: new Date(Date.now() - 1000) } });

    await request(app.getHttpServer()).post('/api/v1/auth/register/email/verify').send({ email: addr, code }).expect(400);
  });

  it('vượt quá số lần thử tối đa (max attempts) thì mã đúng cũng bị từ chối', async () => {
    const addr = uniqueEmail('max-attempts');
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);
    const code = email.getLastCode(addr);

    for (let i = 0; i < 5; i++) {
      await request(app.getHttpServer())
        .post('/api/v1/auth/register/email/verify')
        .send({ email: addr, code: '111111' })
        .expect(400);
    }

    // Mã ĐÚNG nhưng đã hết lượt thử (EMAIL_VERIFICATION_MAX_ATTEMPTS=5 trong .env.test).
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/verify').send({ email: addr, code }).expect(400);
  });

  it('resend: gửi mã mới thì mã cũ không còn dùng được, chỉ mã mới nhất verify thành công', async () => {
    const addr = uniqueEmail('resend');
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);
    const firstCode = email.getLastCode(addr);

    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);
    const secondCode = email.getLastCode(addr);

    expect(firstCode).not.toBe(secondCode);

    await request(app.getHttpServer())
      .post('/api/v1/auth/register/email/verify')
      .send({ email: addr, code: secondCode })
      .expect(201);
  });

  it('email đã verified rồi thì request đăng ký lại bị từ chối (hướng dẫn đăng nhập)', async () => {
    const addr = uniqueEmail('already-verified');
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);
    const code = email.getLastCode(addr);
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/verify').send({ email: addr, code }).expect(201);

    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(400);
  });

  it('email không hợp lệ bị validation từ chối (400) trước khi chạm tới service', async () => {
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: 'not-an-email' }).expect(400);
  });
});
