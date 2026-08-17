import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { ensureBaseFixtures, uniquePhone } from './utils/fixtures';

// Luồng cốt lõi Admin (đặc tả Phase 2 §6.C): dashboard, users, employers, jobs,
// applications, reports, category/area management.
describe('Admin E2E flow', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  let adminToken: string;
  let cityId: string;
  const adminPhone = uniquePhone(3);

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    sms = built.sms;

    const { city } = await ensureBaseFixtures(prisma);
    cityId = city.id;

    // Cấp quyền ADMIN chỉ được thực hiện ngoài luồng tự đăng ký (đặc tả mục 20/32) -
    // ở đây mô phỏng việc admin đã được seed sẵn trong DB trước khi đăng nhập.
    await prisma.user.create({ data: { phone: adminPhone, roles: ['ADMIN'], isPhoneVerified: true } });
  });

  afterAll(async () => {
    await app.close();
  });

  it('logs in as an ADMIN account via OTP', async () => {
    await request(app.getHttpServer()).post('/api/v1/auth/otp/request').send({ phone: adminPhone }).expect(201);
    const code = sms.getLastCode(adminPhone);
    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/otp/verify')
      .send({ phone: adminPhone, code })
      .expect(201);
    adminToken = res.body.accessToken;
  });

  it('reads the dashboard stats', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/admin/dashboard')
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);
    expect(typeof res.body.totalUsers).toBe('number');
    expect(typeof res.body.activeJobs).toBe('number');
  });

  it('lists users, employers, jobs, applications, reports', async () => {
    for (const path of ['users', 'employers', 'jobs', 'applications', 'reports']) {
      const res = await request(app.getHttpServer())
        .get(`/api/v1/admin/${path}`)
        .set('Authorization', `Bearer ${adminToken}`)
        .expect(200);
      expect(Array.isArray(res.body)).toBe(true);
    }
  });

  it('manages job categories', async () => {
    const createRes = await request(app.getHttpServer())
      .post('/api/v1/admin/categories')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ name: 'Danh mục E2E', slug: 'danh-muc-e2e' })
      .expect(201);
    expect(createRes.body.isActive).toBe(true);

    const updateRes = await request(app.getHttpServer())
      .patch(`/api/v1/admin/categories/${createRes.body.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ isActive: false })
      .expect(200);
    expect(updateRes.body.isActive).toBe(false);
  });

  it('manages areas', async () => {
    const createRes = await request(app.getHttpServer())
      .post('/api/v1/admin/areas')
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ cityId, name: 'Khu vực E2E', slug: 'khu-vuc-e2e' })
      .expect(201);
    expect(createRes.body.name).toBe('Khu vực E2E');

    const updateRes = await request(app.getHttpServer())
      .patch(`/api/v1/admin/areas/${createRes.body.id}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .send({ isActive: false })
      .expect(200);
    expect(updateRes.body.isActive).toBe(false);
  });
});
