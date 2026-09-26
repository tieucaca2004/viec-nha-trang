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

  it('shows which job a JOB report is about in the reports list', async () => {
    const area = await prisma.area.findFirstOrThrow({ where: { cityId } });
    const category = await prisma.jobCategory.findFirstOrThrow();
    const employer = await prisma.employerProfile.create({
      data: { businessName: 'Chủ tin admin e2e', user: { create: { phone: uniquePhone() } } },
    });
    const location = await prisma.employerLocation.create({
      data: { employerId: employer.id, name: 'Cơ sở', address: 'x', cityId, areaId: area.id, latitude: 12.2, longitude: 109.1 },
    });
    const job = await prisma.job.create({
      data: {
        employerId: employer.id,
        employerLocationId: location.id,
        categoryId: category.id,
        cityId,
        areaId: area.id,
        latitude: 12.2,
        longitude: 109.1,
        title: 'Tin bị báo cáo - admin e2e',
        headcount: 1,
        employmentType: 'PART_TIME',
        shifts: ['EVENING'],
        salaryMin: 1,
        salaryMax: 2,
        salaryUnit: 'HOUR',
      },
    });
    const reporter = await prisma.user.create({ data: { phone: uniquePhone() } });
    const report = await prisma.report.create({
      data: { reporterId: reporter.id, targetType: 'JOB', jobId: job.id, reason: 'SCAM' },
    });

    const res = await request(app.getHttpServer())
      .get('/api/v1/admin/reports')
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);
    const listed = res.body.find((r: { id: string }) => r.id === report.id);
    expect(listed.job).toEqual({ id: job.id, title: 'Tin bị báo cáo - admin e2e' });
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
