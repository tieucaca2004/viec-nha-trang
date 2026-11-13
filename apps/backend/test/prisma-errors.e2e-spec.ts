import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { ensureBaseFixtures, uniquePhone } from './utils/fixtures';

// Lỗi Prisma "đã biết" (P2002 trùng unique, P2003 tham chiếu không tồn tại, P2025 không tìm thấy,
// dữ liệu sai kiểu) trước đây đều rơi thành 500. PrismaExceptionFilter (APP_FILTER) trả đúng 4xx.
describe('Known Prisma errors are returned as 4xx, not 500', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  let adminToken: string;
  let employerToken: string;
  let seekerToken: string;
  let jobId: string;
  const missingId = '00000000-0000-4000-8000-000000000000';

  async function login(phone: string): Promise<string> {
    await request(app.getHttpServer()).post('/api/v1/auth/otp/request').send({ phone }).expect(201);
    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code: sms.getLastCode(phone) })
      .expect(201);
    return res.body.accessToken;
  }

  async function createJob(title: string): Promise<string> {
    const locations = await request(app.getHttpServer())
      .get('/api/v1/me/employer-profile/locations')
      .set('Authorization', `Bearer ${employerToken}`)
      .expect(200);
    const { category } = await ensureBaseFixtures(prisma);
    const res = await request(app.getHttpServer())
      .post('/api/v1/jobs')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({
        employerLocationId: locations.body[0].id,
        categoryId: category.id,
        title,
        headcount: 1,
        employmentType: 'PART_TIME',
        shifts: ['EVENING'],
        salaryMin: 20000,
        salaryMax: 25000,
        salaryUnit: 'HOUR',
      })
      .expect(201);
    return res.body.id;
  }

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    sms = built.sms;
    const { city, area } = await ensureBaseFixtures(prisma);

    const adminPhone = uniquePhone();
    await prisma.user.create({ data: { phone: adminPhone, roles: ['ADMIN'], isPhoneVerified: true } });
    adminToken = await login(adminPhone);

    employerToken = await login(uniquePhone());
    await request(app.getHttpServer())
      .patch('/api/v1/me/roles')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ role: 'EMPLOYER' })
      .expect(200);
    await request(app.getHttpServer())
      .put('/api/v1/me/employer-profile')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ businessName: 'Chủ tin - Prisma errors test' })
      .expect(200);
    await request(app.getHttpServer())
      .post('/api/v1/me/employer-profile/locations')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ name: 'Cơ sở', address: '1 Test St', cityId: city.id, areaId: area.id, latitude: 12.26, longitude: 109.2 })
      .expect(201);

    seekerToken = await login(uniquePhone());
    await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${seekerToken}`)
      .send({ fullName: 'Ứng viên Prisma errors' })
      .expect(200);

    jobId = await createJob('Tin cho test lỗi Prisma');
  });

  afterAll(async () => {
    await app.close();
  });

  it('saving a job that does not exist returns 404 (FK P2003) and stores nothing', async () => {
    const res = await request(app.getHttpServer())
      .post(`/api/v1/saved-jobs/${missingId}`)
      .set('Authorization', `Bearer ${seekerToken}`)
      .expect(404);
    expect(res.body).toEqual({ statusCode: 404, message: 'Dữ liệu liên quan không tồn tại.', error: 'Not Found' });
    expect(await prisma.savedJob.count({ where: { jobId: missingId } })).toBe(0);
  });

  it('reporting a REVIEW that does not exist returns 404 instead of 500', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/reports')
      .set('Authorization', `Bearer ${seekerToken}`)
      .send({ targetType: 'REVIEW', reviewId: missingId, reason: 'SPAM' })
      .expect(404);
  });

  it('concurrent apply / save on the same job never return 500 and keep exactly one row', async () => {
    const raceJobId = await createJob('Tin cho test race');
    const applies = await Promise.all(
      Array.from({ length: 6 }, () =>
        request(app.getHttpServer()).post(`/api/v1/jobs/${raceJobId}/apply`).set('Authorization', `Bearer ${seekerToken}`),
      ),
    );
    const saves = await Promise.all(
      Array.from({ length: 6 }, () =>
        request(app.getHttpServer()).post(`/api/v1/saved-jobs/${raceJobId}`).set('Authorization', `Bearer ${seekerToken}`),
      ),
    );

    for (const res of [...applies, ...saves]) {
      expect([201, 409]).toContain(res.status);
    }
    expect(applies.some((r) => r.status === 201)).toBe(true);
    expect(await prisma.application.count({ where: { jobId: raceJobId } })).toBe(1);
    expect(await prisma.savedJob.count({ where: { jobId: raceJobId } })).toBe(1);
  });

  describe('admin endpoints', () => {
    it('an unknown job status returns 400 and leaves the job unchanged', async () => {
      await request(app.getHttpServer())
        .patch(`/api/v1/admin/jobs/${jobId}/status`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ status: 'BOGUS' })
        .expect(400);
      expect((await prisma.job.findUniqueOrThrow({ where: { id: jobId } })).status).toBe('ACTIVE');
    });

    it('an unknown verification level returns 400', async () => {
      const employer = await prisma.employerProfile.findFirstOrThrow({ where: { jobs: { some: { id: jobId } } } });
      await request(app.getHttpServer())
        .post(`/api/v1/admin/employers/${employer.id}/verify`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ level: 'BOGUS' })
        .expect(400);
    });

    it('an unknown field in a category update returns 400', async () => {
      const category = await prisma.jobCategory.findFirstOrThrow();
      await request(app.getHttpServer())
        .patch(`/api/v1/admin/categories/${category.id}`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ foo: 1 })
        .expect(400);
    });

    it('acting on records that do not exist returns 404 (P2025)', async () => {
      await request(app.getHttpServer())
        .post(`/api/v1/admin/users/${missingId}/ban`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ reason: 'x' })
        .expect(404);
      await request(app.getHttpServer())
        .patch(`/api/v1/admin/reports/${missingId}/resolve`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ status: 'RESOLVED' })
        .expect(404);
      await request(app.getHttpServer())
        .patch(`/api/v1/admin/jobs/${missingId}/status`)
        .set('Authorization', `Bearer ${adminToken}`)
        .send({ status: 'CLOSED' })
        .expect(404);
    });
  });
});
