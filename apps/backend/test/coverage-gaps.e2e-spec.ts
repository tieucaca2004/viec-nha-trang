import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { ensureBaseFixtures, uniquePhone } from './utils/fixtures';

// Lấp các khoảng trống test coverage nêu trong FULL AUDIT mục 10: illegal state transitions,
// isUrgent filter, reports creation, saved jobs duplicate-save idempotency.
describe('Coverage gaps from FULL AUDIT item 10', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  let employerToken: string;
  let seekerToken: string;
  let categoryId: string;
  let employerLocationId: string;
  const employerPhone = uniquePhone(7);
  const seekerPhone = uniquePhone(7);

  async function loginAndReturnToken(phone: string): Promise<string> {
    await request(app.getHttpServer()).post('/api/v1/auth/otp/request').send({ phone }).expect(201);
    const code = sms.getLastCode(phone);
    const res = await request(app.getHttpServer()).post('/api/v1/auth/otp/verify').send({ phone, code }).expect(201);
    return res.body.accessToken;
  }

  async function createJob(overrides: Record<string, unknown> = {}): Promise<string> {
    const res = await request(app.getHttpServer())
      .post('/api/v1/jobs')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({
        employerLocationId,
        categoryId,
        title: 'Tin coverage-gaps test',
        headcount: 1,
        employmentType: 'PART_TIME',
        shifts: ['EVENING'],
        salaryMin: 20000,
        salaryMax: 25000,
        salaryUnit: 'HOUR',
        ...overrides,
      })
      .expect(201);
    return res.body.id as string;
  }

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    sms = built.sms;

    const { city, area, category } = await ensureBaseFixtures(prisma);
    categoryId = category.id;

    employerToken = await loginAndReturnToken(employerPhone);
    await request(app.getHttpServer())
      .patch('/api/v1/me/roles')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ role: 'EMPLOYER' })
      .expect(200);
    await request(app.getHttpServer())
      .put('/api/v1/me/employer-profile')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ businessName: 'Chủ tin - Coverage Gaps Test' })
      .expect(200);
    const locationRes = await request(app.getHttpServer())
      .post('/api/v1/me/employer-profile/locations')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ name: 'Cơ sở', address: '1 Test St', cityId: city.id, areaId: area.id, latitude: 12.26, longitude: 109.2 })
      .expect(201);
    employerLocationId = locationRes.body.id;

    seekerToken = await loginAndReturnToken(seekerPhone);
    await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${seekerToken}`)
      .send({ fullName: 'Ứng viên Coverage Gaps' })
      .expect(200);
  });

  afterAll(async () => {
    await app.close();
  });

  describe('Application illegal state transitions', () => {
    it('rejects NEW -> HIRED (skipping VIEWED/CONTACTED/INTERVIEW) with 400', async () => {
      const jobId = await createJob({ title: 'Illegal transition test 1' });
      const applyRes = await request(app.getHttpServer())
        .post(`/api/v1/jobs/${jobId}/apply`)
        .set('Authorization', `Bearer ${seekerToken}`)
        .expect(201);

      await request(app.getHttpServer())
        .patch(`/api/v1/applications/${applyRes.body.id}/status`)
        .set('Authorization', `Bearer ${employerToken}`)
        .send({ status: 'HIRED' })
        .expect(400);
    });

    it('rejects any transition out of a terminal state (HIRED -> VIEWED) with 400', async () => {
      const jobId = await createJob({ title: 'Illegal transition test 2' });
      const applyRes = await request(app.getHttpServer())
        .post(`/api/v1/jobs/${jobId}/apply`)
        .set('Authorization', `Bearer ${seekerToken}`)
        .expect(201);
      const applicationId = applyRes.body.id;

      for (const status of ['VIEWED', 'CONTACTED', 'INTERVIEW', 'HIRED']) {
        await request(app.getHttpServer())
          .patch(`/api/v1/applications/${applicationId}/status`)
          .set('Authorization', `Bearer ${employerToken}`)
          .send({ status })
          .expect(200);
      }

      await request(app.getHttpServer())
        .patch(`/api/v1/applications/${applicationId}/status`)
        .set('Authorization', `Bearer ${employerToken}`)
        .send({ status: 'VIEWED' })
        .expect(400);
    });

    it('rejects NOT_SUITABLE -> anything (terminal state) with 400', async () => {
      const jobId = await createJob({ title: 'Illegal transition test 3' });
      const applyRes = await request(app.getHttpServer())
        .post(`/api/v1/jobs/${jobId}/apply`)
        .set('Authorization', `Bearer ${seekerToken}`)
        .expect(201);
      const applicationId = applyRes.body.id;

      await request(app.getHttpServer())
        .patch(`/api/v1/applications/${applicationId}/status`)
        .set('Authorization', `Bearer ${employerToken}`)
        .send({ status: 'NOT_SUITABLE' })
        .expect(200);

      await request(app.getHttpServer())
        .patch(`/api/v1/applications/${applicationId}/status`)
        .set('Authorization', `Bearer ${employerToken}`)
        .send({ status: 'CONTACTED' })
        .expect(400);
    });
  });

  describe('isUrgent filter', () => {
    it('GET /jobs?isUrgent=true returns only urgent jobs and excludes non-urgent ones', async () => {
      const urgentJobId = await createJob({ title: 'Tin gấp - coverage test', isUrgent: true });
      const normalJobId = await createJob({ title: 'Tin thường - coverage test', isUrgent: false });

      const res = await request(app.getHttpServer())
        .get('/api/v1/jobs')
        .query({ isUrgent: 'true', limit: 50 })
        .expect(200);

      const ids: string[] = res.body.data.map((j: { id: string }) => j.id);
      expect(ids).toContain(urgentJobId);
      expect(ids).not.toContain(normalJobId);
      expect(res.body.data.every((j: { isUrgent: boolean }) => j.isUrgent === true)).toBe(true);
    });

    it('GET /jobs without isUrgent returns both urgent and non-urgent jobs', async () => {
      const urgentJobId = await createJob({ title: 'Tin gấp 2 - coverage test', isUrgent: true });
      const normalJobId = await createJob({ title: 'Tin thường 2 - coverage test', isUrgent: false });

      const res = await request(app.getHttpServer()).get('/api/v1/jobs').query({ limit: 50 }).expect(200);
      const ids: string[] = res.body.data.map((j: { id: string }) => j.id);
      expect(ids).toContain(urgentJobId);
      expect(ids).toContain(normalJobId);
    });
  });

  describe('salaryMin/salaryMax filter (sửa lỗi High #9 FULL AUDIT - filter lương ở mobile)', () => {
    it('GET /jobs?salaryMax= excludes jobs whose salaryMin is above the requested max', async () => {
      const cheapJobId = await createJob({ title: 'Lương thấp - coverage test', salaryMin: 15000, salaryMax: 20000 });
      const expensiveJobId = await createJob({ title: 'Lương cao - coverage test', salaryMin: 80000, salaryMax: 100000 });

      const res = await request(app.getHttpServer()).get('/api/v1/jobs').query({ salaryMax: 25000, limit: 50 }).expect(200);
      const ids: string[] = res.body.data.map((j: { id: string }) => j.id);
      expect(ids).toContain(cheapJobId);
      expect(ids).not.toContain(expensiveJobId);
    });

    it('GET /jobs?salaryMin=&salaryMax= together only return jobs whose range overlaps the requested band', async () => {
      const tooLowId = await createJob({ title: 'Quá thấp - coverage test', salaryMin: 10000, salaryMax: 15000 });
      const inRangeId = await createJob({ title: 'Đúng khoảng - coverage test', salaryMin: 30000, salaryMax: 40000 });
      const tooHighId = await createJob({ title: 'Quá cao - coverage test', salaryMin: 90000, salaryMax: 100000 });

      const res = await request(app.getHttpServer())
        .get('/api/v1/jobs')
        .query({ salaryMin: 25000, salaryMax: 50000, limit: 50 })
        .expect(200);
      const ids: string[] = res.body.data.map((j: { id: string }) => j.id);
      expect(ids).toContain(inRangeId);
      expect(ids).not.toContain(tooLowId);
      expect(ids).not.toContain(tooHighId);
    });
  });

  describe('Reports creation', () => {
    it('creates a report against a job and persists it', async () => {
      const jobId = await createJob({ title: 'Tin bị báo cáo - coverage test' });

      const res = await request(app.getHttpServer())
        .post('/api/v1/reports')
        .set('Authorization', `Bearer ${seekerToken}`)
        .send({ targetType: 'JOB', jobId, reason: 'FAKE_JOB', note: 'Tin này có vẻ giả' })
        .expect(201);

      expect(res.body.targetType).toBe('JOB');
      expect(res.body.status).toBe('OPEN');

      const stored = await prisma.report.findUniqueOrThrow({ where: { id: res.body.id } });
      expect(stored.jobId).toBe(jobId);
      expect(stored.reason).toBe('FAKE_JOB');
    });

    it('rejects an unauthenticated report attempt with 401', async () => {
      await request(app.getHttpServer())
        .post('/api/v1/reports')
        .send({ targetType: 'JOB', reason: 'SPAM' })
        .expect(401);
    });
  });

  describe('Saved jobs duplicate-save idempotency', () => {
    it('saving the same job twice in a row does not create a duplicate or error', async () => {
      const jobId = await createJob({ title: 'Tin lưu 2 lần - coverage test' });

      await request(app.getHttpServer())
        .post(`/api/v1/saved-jobs/${jobId}`)
        .set('Authorization', `Bearer ${seekerToken}`)
        .expect(201);
      await request(app.getHttpServer())
        .post(`/api/v1/saved-jobs/${jobId}`)
        .set('Authorization', `Bearer ${seekerToken}`)
        .expect(201);

      const list = await request(app.getHttpServer())
        .get('/api/v1/saved-jobs')
        .set('Authorization', `Bearer ${seekerToken}`)
        .expect(200);

      const matches = list.body.filter((s: { jobId: string }) => s.jobId === jobId);
      expect(matches).toHaveLength(1);
    });
  });
});
