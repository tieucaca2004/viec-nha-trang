import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingEmailProvider } from './utils/capturing-email.provider';
import { uniqueEmail } from './utils/fixtures';

/**
 * Đăng nhập bằng email OTP qua route RIÊNG `/auth/login/email/request|verify` (tách khỏi
 * `/auth/register/email/request|verify` để không ăn chung throttle bucket - xem
 * otp-rate-limit.e2e-spec.ts). Cùng logic nghiệp vụ với đăng ký (AuthService.requestEmailVerification/
 * verifyEmailAndRegister) nên các test correctness OTP (mã sai/hết hạn/max attempts/reuse) đã có
 * đầy đủ ở email-verification.e2e-spec.ts cho route đăng ký; suite này chỉ chứng minh route đăng
 * nhập hoạt động ĐÚNG và ĐỘC LẬP.
 */
describe('Đăng nhập email OTP - route riêng /auth/login/email', () => {
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

  it('H/I. tài khoản ĐÃ TỒN TẠI (email verified) đăng nhập qua route login -> nhận JWT thật, không tạo tài khoản mới', async () => {
    const addr = uniqueEmail('login-route-existing');

    // Tạo tài khoản qua route đăng ký trước.
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);
    const registerRes = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email/verify')
      .send({ email: addr, code: email.getLastCode(addr) })
      .expect(201);
    const userId = (await prisma.user.findUniqueOrThrow({ where: { email: addr } })).id;

    // Đăng nhập qua route RIÊNG /auth/login/email/*.
    const loginReqRes = await request(app.getHttpServer()).post('/api/v1/auth/login/email/request').send({ email: addr }).expect(201);
    expect(loginReqRes.body).toEqual({ expiresInSeconds: expect.any(Number) });

    const loginCode = email.getLastCode(addr);
    const loginRes = await request(app.getHttpServer())
      .post('/api/v1/auth/login/email/verify')
      .send({ email: addr, code: loginCode })
      .expect(201);

    expect(loginRes.body.accessToken).toBeTruthy();
    expect(loginRes.body.refreshToken).toBeTruthy();
    expect(loginRes.body.refreshToken).not.toBe(registerRes.body.refreshToken);

    const users = await prisma.user.findMany({ where: { email: addr } });
    expect(users).toHaveLength(1);
    expect(users[0].id).toBe(userId);
  });

  it('J. email CHƯA từng đăng ký gọi route login -> vẫn 201, KHÔNG lộ existence (anti-enumeration)', async () => {
    const knownAddr = uniqueEmail('login-route-known');
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: knownAddr }).expect(201);
    await request(app.getHttpServer())
      .post('/api/v1/auth/register/email/verify')
      .send({ email: knownAddr, code: email.getLastCode(knownAddr) })
      .expect(201);

    const knownRes = await request(app.getHttpServer()).post('/api/v1/auth/login/email/request').send({ email: knownAddr }).expect(201);
    const unknownRes = await request(app.getHttpServer())
      .post('/api/v1/auth/login/email/request')
      .send({ email: uniqueEmail('login-route-unknown') })
      .expect(201);

    expect(knownRes.body).toEqual(unknownRes.body);
  });

  it('J2. verify OTP đăng nhập cho email chưa từng tồn tại -> tạo tài khoản mới hợp lệ, KHÔNG crash', async () => {
    const addr = uniqueEmail('login-route-autocreate');
    await request(app.getHttpServer()).post('/api/v1/auth/login/email/request').send({ email: addr }).expect(201);
    const code = email.getLastCode(addr);

    const res = await request(app.getHttpServer()).post('/api/v1/auth/login/email/verify').send({ email: addr, code }).expect(201);
    expect(res.body.accessToken).toBeTruthy();

    const user = await prisma.user.findUniqueOrThrow({ where: { email: addr } });
    expect(user.roles).toContain('JOB_SEEKER');
  });

  it('K. mã OTP sai ở route login bị từ chối 400, không cấp token', async () => {
    const addr = uniqueEmail('login-route-wrong-code');
    await request(app.getHttpServer()).post('/api/v1/auth/login/email/request').send({ email: addr }).expect(201);

    await request(app.getHttpServer()).post('/api/v1/auth/login/email/verify').send({ email: addr, code: '000000' }).expect(400);
  });

  it('L. mã OTP hết hạn ở route login bị từ chối', async () => {
    const addr = uniqueEmail('login-route-expired');
    await request(app.getHttpServer()).post('/api/v1/auth/login/email/request').send({ email: addr }).expect(201);
    const code = email.getLastCode(addr);

    await prisma.emailVerificationCode.updateMany({ where: { email: addr }, data: { expiresAt: new Date(Date.now() - 1000) } });

    await request(app.getHttpServer()).post('/api/v1/auth/login/email/verify').send({ email: addr, code }).expect(400);
  });

  it('M. mã OTP đã dùng (reuse) ở route login bị từ chối', async () => {
    const addr = uniqueEmail('login-route-reuse');
    await request(app.getHttpServer()).post('/api/v1/auth/login/email/request').send({ email: addr }).expect(201);
    const code = email.getLastCode(addr);

    await request(app.getHttpServer()).post('/api/v1/auth/login/email/verify').send({ email: addr, code }).expect(201);
    // Dùng lại đúng mã đó lần nữa -> phải bị từ chối (đã consumedAt).
    await request(app.getHttpServer()).post('/api/v1/auth/login/email/verify').send({ email: addr, code }).expect(400);
  });

  it('email không hợp lệ ở route login bị validation từ chối trước khi chạm service', async () => {
    await request(app.getHttpServer()).post('/api/v1/auth/login/email/request').send({ email: 'khong-phai-email' }).expect(400);
  });
});
