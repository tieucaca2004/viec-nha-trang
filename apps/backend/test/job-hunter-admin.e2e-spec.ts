import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { ensureBaseFixtures, uniquePhone } from './utils/fixtures';

// Đặc tả JobHunter Phần 9: admin phải xem được tổng số job theo sourceType (USER_CREATED/
// IMPORTED/SYNTHETIC), theo status (pending/published/expired), số lượng duplicate, và filter
// jobs list theo sourceType - dữ liệu synthetic KHÔNG được lẫn với dữ liệu người dùng thật.
describe('Admin - JobHunter data overview & source filter (Phần 9) - e2e', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  let adminToken: string;
  const adminPhone = uniquePhone(7);

  let userCreatedJobId: string;
  let syntheticJobId: string;
  let importedJobId: string;

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    sms = built.sms;

    const { area, category, city } = await ensureBaseFixtures(prisma);
    await prisma.user.create({ data: { phone: adminPhone, roles: ['ADMIN'], isPhoneVerified: true } });

    // Test DB không chạy prisma/seed.ts (chỉ migrate deploy) - tự đảm bảo có đủ JobSource cần
    // kiểm tra, độc lập với seed script chính (giống cách test khác tự tạo fixture riêng).
    await prisma.jobSource.upsert({
      where: { name: 'user_created' },
      update: {},
      create: { name: 'user_created', type: 'USER_CREATED', status: 'ACTIVE', enabled: true },
    });
    await prisma.jobSource.upsert({
      where: { name: 'synthetic' },
      update: {},
      create: { name: 'synthetic', type: 'SYNTHETIC', status: 'ACTIVE', enabled: true },
    });
    await prisma.jobSource.upsert({
      where: { name: 'facebook_job_groups' },
      update: {},
      create: { name: 'facebook_job_groups', type: 'FACEBOOK', status: 'UNSUPPORTED', enabled: false },
    });

    const employerUser = await prisma.user.create({
      data: { email: 'job-hunter-admin-test-employer@example.test', roles: ['EMPLOYER'], authProvider: 'EMAIL' },
    });
    const employer = await prisma.employerProfile.create({
      data: { userId: employerUser.id, businessName: 'Test Employer For Admin Overview' },
    });
    const location = await prisma.employerLocation.create({
      data: { employerId: employer.id, name: 'Test Location', address: 'Test', cityId: city.id, areaId: area.id, latitude: 0, longitude: 0 },
    });

    const baseJobData = {
      employerId: employer.id,
      employerLocationId: location.id,
      categoryId: category.id,
      cityId: city.id,
      areaId: area.id,
      latitude: 0,
      longitude: 0,
      employmentType: 'FULL_TIME' as const,
      salaryMin: 5_000_000,
      salaryMax: 7_000_000,
      salaryUnit: 'MONTH' as const,
    };

    const userJob = await prisma.job.create({ data: { ...baseJobData, title: 'Job người dùng thật đăng', status: 'ACTIVE' } });
    userCreatedJobId = userJob.id;

    const syntheticJob = await prisma.job.create({
      data: {
        ...baseJobData,
        title: 'Job tổng hợp test overview',
        status: 'PENDING_REVIEW',
        sourceType: 'SYNTHETIC',
        sourceName: 'synthetic',
        sourceJobId: 'admin-overview-test-synth-1',
      },
    });
    syntheticJobId = syntheticJob.id;

    const importedJob = await prisma.job.create({
      data: {
        ...baseJobData,
        title: 'Job imported test overview',
        status: 'EXPIRED',
        sourceType: 'IMPORTED',
        sourceName: 'careerviet',
        sourceUrl: 'https://careerviet.vn/jobs/admin-overview-test',
        sourceJobId: 'admin-overview-test-imported-1',
      },
    });
    importedJobId = importedJob.id;

    // Job thứ 2 trùng với importedJob để test duplicate count.
    await prisma.job.create({
      data: {
        ...baseJobData,
        title: 'Job imported duplicate test overview',
        status: 'ACTIVE',
        sourceType: 'IMPORTED',
        sourceName: 'topcv',
        sourceJobId: 'admin-overview-test-imported-dupe',
        duplicateOfId: importedJob.id,
      },
    });
  });

  afterAll(async () => {
    await app.close();
  });

  it('logs in as ADMIN', async () => {
    await request(app.getHttpServer()).post('/api/v1/auth/otp/request').send({ phone: adminPhone }).expect(201);
    const code = sms.getLastCode(adminPhone);
    const res = await request(app.getHttpServer()).post('/api/v1/auth/otp/verify').send({ phone: adminPhone, code }).expect(201);
    adminToken = res.body.accessToken;
  });

  it('GET /admin/jobs/data-overview trả về đúng số lượng theo sourceType/status/duplicate', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/admin/jobs/data-overview')
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);

    expect(res.body.bySourceType.USER_CREATED).toBeGreaterThanOrEqual(1);
    expect(res.body.bySourceType.SYNTHETIC).toBeGreaterThanOrEqual(1);
    expect(res.body.bySourceType.IMPORTED).toBeGreaterThanOrEqual(2);
    expect(res.body.byStatus.pendingReview).toBeGreaterThanOrEqual(1);
    expect(res.body.byStatus.expired).toBeGreaterThanOrEqual(1);
    expect(res.body.duplicate).toBeGreaterThanOrEqual(1);
    expect(res.body.total).toBeGreaterThanOrEqual(4);
  });

  it('GET /admin/jobs?sourceType=SYNTHETIC chỉ trả về job synthetic, không lẫn job thật', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/admin/jobs?sourceType=SYNTHETIC&take=100')
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);

    const ids: string[] = res.body.map((j: { id: string }) => j.id);
    expect(ids).toContain(syntheticJobId);
    expect(ids).not.toContain(userCreatedJobId);
    expect(ids).not.toContain(importedJobId);
    expect(res.body.every((j: { sourceType: string }) => j.sourceType === 'SYNTHETIC')).toBe(true);
  });

  it('GET /admin/jobs?sourceType=USER_CREATED không lẫn job synthetic/imported', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/admin/jobs?sourceType=USER_CREATED&take=100')
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);

    const ids: string[] = res.body.map((j: { id: string }) => j.id);
    expect(ids).toContain(userCreatedJobId);
    expect(ids).not.toContain(syntheticJobId);
    expect(ids).not.toContain(importedJobId);
  });

  it('GET /admin/job-sources trả về source registry (đặc tả Phần 5/6)', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/admin/job-sources')
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);

    const names: string[] = res.body.map((s: { name: string }) => s.name);
    expect(names).toContain('user_created');
    expect(names).toContain('synthetic');
    const facebookSource = res.body.find((s: { name: string }) => s.name === 'facebook_job_groups');
    expect(facebookSource?.status).toBe('UNSUPPORTED');
  });

  it('không phải ADMIN thì không truy cập được data-overview', async () => {
    await request(app.getHttpServer()).get('/api/v1/admin/jobs/data-overview').expect(401);
  });
});
