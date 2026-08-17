import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { uniquePhone } from './utils/fixtures';

// Sửa lỗi High #7 (FULL AUDIT): trước đây không có POST /auth/logout - "đăng xuất" chỉ xoá token
// phía client, refresh token vẫn dùng được trên server. Suite này chứng minh: logout thu hồi
// refresh token thật (không dùng lại được để lấy access token mới), idempotent, và không throw
// với input rác.
describe('POST /auth/logout - High fix #7', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  const phone = uniquePhone(8);

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    sms = built.sms;
  });

  afterAll(async () => {
    await app.close();
  });

  async function login() {
    await request(app.getHttpServer()).post('/api/v1/auth/otp/request').send({ phone }).expect(201);
    const code = sms.getLastCode(phone);
    const res = await request(app.getHttpServer()).post('/api/v1/auth/otp/verify').send({ phone, code }).expect(201);
    return res.body as { accessToken: string; refreshToken: string };
  }

  it('revokes the refresh token server-side so it can no longer mint a new access token', async () => {
    const { refreshToken } = await login();

    await request(app.getHttpServer()).post('/api/v1/auth/logout').send({ refreshToken }).expect(201);

    await request(app.getHttpServer()).post('/api/v1/auth/refresh').send({ refreshToken }).expect(401);
  });

  it('is idempotent - calling logout twice with the same (already revoked) token still succeeds', async () => {
    const { refreshToken } = await login();

    await request(app.getHttpServer()).post('/api/v1/auth/logout').send({ refreshToken }).expect(201);
    await request(app.getHttpServer()).post('/api/v1/auth/logout').send({ refreshToken }).expect(201);
  });

  it('does not throw for a garbage/malformed refresh token (still 201, no server error)', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/auth/logout')
      .send({ refreshToken: 'not-a-real-jwt-at-all' })
      .expect(201);
  });

  it('only revokes the specific token used, not every session of the user', async () => {
    // Đăng nhập 2 lần liên tiếp (giả lập 2 thiết bị) - mỗi lần issueTokens tạo 1 refreshToken row riêng.
    const session1 = await login();
    const session2 = await login();

    await request(app.getHttpServer()).post('/api/v1/auth/logout').send({ refreshToken: session1.refreshToken }).expect(201);

    // Session 1 bị thu hồi.
    await request(app.getHttpServer()).post('/api/v1/auth/refresh').send({ refreshToken: session1.refreshToken }).expect(401);
    // Session 2 (thiết bị khác) không bị ảnh hưởng.
    await request(app.getHttpServer()).post('/api/v1/auth/refresh').send({ refreshToken: session2.refreshToken }).expect(201);
  });

  it('persists the revocation in the database (revokedAt set)', async () => {
    const { refreshToken } = await login();
    const before = await prisma.refreshToken.findMany({ where: { revokedAt: null } });

    await request(app.getHttpServer()).post('/api/v1/auth/logout').send({ refreshToken }).expect(201);

    const after = await prisma.refreshToken.findMany({ where: { revokedAt: null } });
    expect(after.length).toBe(before.length - 1);
  });
});
