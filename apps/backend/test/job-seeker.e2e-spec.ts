import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { ensureBaseFixtures, uniquePhone } from './utils/fixtures';

// Luồng cốt lõi Người tìm việc (đặc tả Phase 2 §6.A): đăng nhập OTP, hồ sơ, tìm/lọc việc,
// xem chi tiết, lưu/bỏ lưu, ứng tuyển 1 chạm, theo dõi trạng thái ứng tuyển.
describe('Job seeker E2E flow', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  let jobId: string;
  let accessToken: string;
  const phone = uniquePhone(1);

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    sms = built.sms;

    const { area, category } = await ensureBaseFixtures(prisma);

    // Tạo sẵn 1 employer + location + job qua Prisma (không phải trọng tâm suite này -
    // luồng đăng tin thật được test riêng ở employer.e2e-spec.ts).
    const employerUser = await prisma.user.create({
      data: { phone: uniquePhone(1), roles: ['EMPLOYER'], isPhoneVerified: true },
    });
    const employer = await prisma.employerProfile.create({
      data: { userId: employerUser.id, businessName: 'Quán Test Vĩnh Hải' },
    });
    const location = await prisma.employerLocation.create({
      data: {
        employerId: employer.id,
        name: 'Cơ sở test',
        address: '1 Test St',
        cityId: area.cityId,
        areaId: area.id,
        latitude: 12.25,
        longitude: 109.19,
      },
    });
    const job = await prisma.job.create({
      data: {
        employerId: employer.id,
        employerLocationId: location.id,
        categoryId: category.id,
        cityId: area.cityId,
        areaId: area.id,
        latitude: 12.25,
        longitude: 109.19,
        title: 'Phục vụ nhà hàng test',
        headcount: 2,
        employmentType: 'PART_TIME',
        shifts: ['EVENING'],
        salaryMin: 28000,
        salaryMax: 32000,
        salaryUnit: 'HOUR',
        status: 'ACTIVE',
        publishedAt: new Date(),
      },
    });
    jobId = job.id;
  });

  afterAll(async () => {
    await app.close();
  });

  it('requests and verifies OTP to obtain a JWT (register/login)', async () => {
    await request(app.getHttpServer()).post('/api/v1/auth/otp/request').send({ phone }).expect(201);

    const code = sms.getLastCode(phone);
    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code })
      .expect(201);

    expect(res.body.accessToken).toEqual(expect.any(String));
    expect(res.body.refreshToken).toEqual(expect.any(String));
    accessToken = res.body.accessToken;
  });

  it('fetches own profile via GET /me', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/me')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    expect(res.body.phone).toBe(phone);
    expect(res.body.roles).toContain('JOB_SEEKER');
    expect(res.body.jobSeekerProfile).toBeNull();
  });

  it('creates/updates the job seeker profile (no CV required)', async () => {
    const res = await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${accessToken}`)
      .send({ fullName: 'Ứng viên Test', experienceLevel: 'NONE' })
      .expect(200);

    expect(res.body.fullName).toBe('Ứng viên Test');
  });

  it('searches jobs by keyword', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/jobs')
      .query({ keyword: 'Phục vụ nhà hàng test' })
      .expect(200);

    expect(res.body.data.some((j: { id: string }) => j.id === jobId)).toBe(true);
  });

  it('filters jobs by employment type', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/jobs')
      .query({ employmentType: 'PART_TIME' })
      .expect(200);

    expect(res.body.data.length).toBeGreaterThan(0);
    for (const job of res.body.data) {
      expect(job.employmentType).toBe('PART_TIME');
    }
  });

  it('views job detail', async () => {
    const res = await request(app.getHttpServer()).get(`/api/v1/jobs/${jobId}`).expect(200);
    expect(res.body.id).toBe(jobId);
    expect(res.body.salaryMin).toBe(28000);
  });

  it('saves and unsaves a job', async () => {
    await request(app.getHttpServer())
      .post(`/api/v1/saved-jobs/${jobId}`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);

    const savedRes = await request(app.getHttpServer())
      .get('/api/v1/saved-jobs')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);
    expect(savedRes.body.some((s: { jobId: string }) => s.jobId === jobId)).toBe(true);

    await request(app.getHttpServer())
      .delete(`/api/v1/saved-jobs/${jobId}`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    const savedRes2 = await request(app.getHttpServer())
      .get('/api/v1/saved-jobs')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);
    expect(savedRes2.body.some((s: { jobId: string }) => s.jobId === jobId)).toBe(false);
  });

  it('applies to a job with one tap', async () => {
    const res = await request(app.getHttpServer())
      .post(`/api/v1/jobs/${jobId}/apply`)
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(201);

    expect(res.body.jobId).toBe(jobId);
    expect(res.body.status).toBe('NEW');
  });

  it('tracks application status via GET /applications/me', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/applications/me')
      .set('Authorization', `Bearer ${accessToken}`)
      .expect(200);

    const application = res.body.find((a: { job: { id: string } }) => a.job?.id === jobId);
    expect(application).toBeDefined();
    expect(application.status).toBe('NEW');
  });
});
