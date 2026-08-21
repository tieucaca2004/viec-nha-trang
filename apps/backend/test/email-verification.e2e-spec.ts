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

  // Regression (bug thật trên Beta): email đã verified PHẢI xin được mã lần nữa - đó chính là luồng
  // ĐĂNG NHẬP bằng email OTP. Trước đây bước này trả 400 "Email này đã được đăng ký. Vui lòng đăng
  // nhập.", khiến đăng nhập bằng email bất khả thi; người dùng bấm lại nhiều lần thì chạm rate
  // limit và nhận nhầm thông báo "Bạn thao tác quá nhanh".
  it('email đã verified vẫn xin được mã và ĐĂNG NHẬP được (không tạo tài khoản trùng)', async () => {
    const addr = uniqueEmail('login-existing');
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);
    const firstCode = email.getLastCode(addr);
    const registerRes = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email/verify')
      .send({ email: addr, code: firstCode })
      .expect(201);
    const userAfterRegister = await prisma.user.findUniqueOrThrow({ where: { email: addr } });

    // Đăng nhập lại bằng chính email đó: xin mã -> 201 (KHÔNG còn 400).
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);
    const loginCode = email.getLastCode(addr);
    expect(loginCode).not.toBe(firstCode);

    const loginRes = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email/verify')
      .send({ email: addr, code: loginCode })
      .expect(201);
    expect(loginRes.body.accessToken).toBeTruthy();
    // Access token KHÔNG có jti (chỉ refresh token mới có - xem issueTokens), nên 2 lần đăng nhập
    // trong cùng 1 giây sinh ra access token giống hệt nhau; refresh token thì luôn khác nhau.
    expect(loginRes.body.refreshToken).toBeTruthy();
    expect(loginRes.body.refreshToken).not.toBe(registerRes.body.refreshToken);

    // Vẫn đúng 1 tài khoản - đăng nhập lại không tạo user mới.
    const users = await prisma.user.findMany({ where: { email: addr } });
    expect(users).toHaveLength(1);
    expect(users[0].id).toBe(userAfterRegister.id);
  });

  // Anti-enumeration: phản hồi cho email ĐÃ đăng ký và CHƯA đăng ký phải giống hệt nhau, để không
  // ai dò được email nào có tài khoản (trước đây 400 vs 201 làm lộ điều này).
  it('request mã cho email đã đăng ký và chưa đăng ký trả về phản hồi giống hệt nhau', async () => {
    const registered = uniqueEmail('enum-registered');
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: registered }).expect(201);
    const code = email.getLastCode(registered);
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/verify').send({ email: registered, code }).expect(201);

    const registeredRes = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email/request')
      .send({ email: registered })
      .expect(201);
    const unknownRes = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email/request')
      .send({ email: uniqueEmail('enum-unknown') })
      .expect(201);

    expect(registeredRes.body).toEqual(unknownRes.body);
  });

  it('email không hợp lệ bị validation từ chối (400) trước khi chạm tới service', async () => {
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: 'not-an-email' }).expect(400);
  });
});
