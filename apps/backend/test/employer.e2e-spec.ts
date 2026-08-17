import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { ensureBaseFixtures, uniquePhone } from './utils/fixtures';

// Luồng cốt lõi Nhà tuyển dụng (đặc tả Phase 2 §6.B): đăng nhập, hồ sơ cơ sở, đăng tin,
// xem tin của mình, xem ứng viên, đổi trạng thái ứng viên qua state machine (mục 16).
describe('Employer E2E flow', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  let employerToken: string;
  let jobId: string;
  let categoryId: string;
  let cityId: string;
  let areaId: string;
  const employerPhone = uniquePhone(2);
  const seekerPhone = uniquePhone(2);

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    sms = built.sms;

    const { city, area, category } = await ensureBaseFixtures(prisma);
    cityId = city.id;
    areaId = area.id;
    categoryId = category.id;
  });

  afterAll(async () => {
    await app.close();
  });

  it('logs in and switches account into employer role', async () => {
    await request(app.getHttpServer()).post('/api/v1/auth/otp/request').send({ phone: employerPhone }).expect(201);
    const code = sms.getLastCode(employerPhone);
    const loginRes = await request(app.getHttpServer())
      .post('/api/v1/auth/otp/verify')
      .send({ phone: employerPhone, code })
      .expect(201);
    employerToken = loginRes.body.accessToken;

    // Tài khoản mặc định là JOB_SEEKER (mục 5) - chuyển sang thêm vai trò EMPLOYER, không tạo tài khoản mới.
    await request(app.getHttpServer())
      .patch('/api/v1/me/roles')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ role: 'EMPLOYER' })
      .expect(200);

    const me = await request(app.getHttpServer())
      .get('/api/v1/me')
      .set('Authorization', `Bearer ${employerToken}`)
      .expect(200);
    expect(me.body.roles).toEqual(expect.arrayContaining(['JOB_SEEKER', 'EMPLOYER']));
  });

  it('returns 404 for employer profile before it is created', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/me/employer-profile')
      .set('Authorization', `Bearer ${employerToken}`)
      .expect(404);
  });

  it('creates the employer business profile and a location', async () => {
    const profileRes = await request(app.getHttpServer())
      .put('/api/v1/me/employer-profile')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ businessName: 'Quán E2E Test' })
      .expect(200);
    expect(profileRes.body.businessName).toBe('Quán E2E Test');

    const locationRes = await request(app.getHttpServer())
      .post('/api/v1/me/employer-profile/locations')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({
        name: 'Cơ sở chính',
        address: '99 Test St',
        cityId,
        areaId,
        latitude: 12.26,
        longitude: 109.2,
      })
      .expect(201);
    expect(locationRes.body.id).toEqual(expect.any(String));
  });

  it('publishes a job posting with all MVP wizard fields', async () => {
    const locations = await request(app.getHttpServer())
      .get('/api/v1/me/employer-profile/locations')
      .set('Authorization', `Bearer ${employerToken}`)
      .expect(200);
    const employerLocationId = locations.body[0].id;

    const res = await request(app.getHttpServer())
      .post('/api/v1/jobs')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({
        employerLocationId,
        categoryId,
        title: 'Phục vụ ca tối',
        headcount: 2,
        employmentType: 'PART_TIME',
        shifts: ['EVENING'],
        shiftStartTime: '17:00',
        shiftEndTime: '22:00',
        salaryMin: 28000,
        salaryMax: 32000,
        salaryUnit: 'HOUR',
        startUrgency: 'IMMEDIATE',
        requiredExperience: 'NOT_REQUIRED',
        isUrgent: true,
      })
      .expect(201);

    expect(res.body.status).toBe('ACTIVE');
    expect(res.body.salaryMin).toBe(28000);
    jobId = res.body.id;
  });

  it('rejects job creation missing the mandatory salary fields', async () => {
    const locations = await request(app.getHttpServer())
      .get('/api/v1/me/employer-profile/locations')
      .set('Authorization', `Bearer ${employerToken}`)
      .expect(200);
    const employerLocationId = locations.body[0].id;

    await request(app.getHttpServer())
      .post('/api/v1/jobs')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({
        employerLocationId,
        categoryId,
        title: 'Thiếu lương',
        headcount: 1,
        employmentType: 'PART_TIME',
        shifts: ['EVENING'],
        salaryUnit: 'HOUR',
        // salaryMin/salaryMax cố tình thiếu - lương là bắt buộc (mục 21)
      })
      .expect(400);
  });

  it('lists jobs posted by the employer', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/jobs/mine')
      .set('Authorization', `Bearer ${employerToken}`)
      .expect(200);
    expect(res.body.some((j: { id: string }) => j.id === jobId)).toBe(true);
  });

  it('receives an applicant and walks the status pipeline NEW → VIEWED → CONTACTED → INTERVIEW → HIRED', async () => {
    await request(app.getHttpServer()).post('/api/v1/auth/otp/request').send({ phone: seekerPhone }).expect(201);
    const seekerCode = sms.getLastCode(seekerPhone);
    const seekerLogin = await request(app.getHttpServer())
      .post('/api/v1/auth/otp/verify')
      .send({ phone: seekerPhone, code: seekerCode })
      .expect(201);
    const seekerToken = seekerLogin.body.accessToken;

    await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${seekerToken}`)
      .send({ fullName: 'Ứng viên cho Employer Test' })
      .expect(200);

    const applyRes = await request(app.getHttpServer())
      .post(`/api/v1/jobs/${jobId}/apply`)
      .set('Authorization', `Bearer ${seekerToken}`)
      .expect(201);
    const applicationId = applyRes.body.id;

    const applicantsRes = await request(app.getHttpServer())
      .get(`/api/v1/employer/jobs/${jobId}/applications`)
      .set('Authorization', `Bearer ${employerToken}`)
      .expect(200);
    expect(applicantsRes.body.some((a: { id: string }) => a.id === applicationId)).toBe(true);

    const transitions: Array<'VIEWED' | 'CONTACTED' | 'INTERVIEW' | 'HIRED'> = [
      'VIEWED',
      'CONTACTED',
      'INTERVIEW',
      'HIRED',
    ];
    for (const status of transitions) {
      const res = await request(app.getHttpServer())
        .patch(`/api/v1/applications/${applicationId}/status`)
        .set('Authorization', `Bearer ${employerToken}`)
        .send({ status })
        .expect(200);
      expect(res.body.status).toBe(status);
    }

    const jobAfter = await request(app.getHttpServer()).get(`/api/v1/jobs/${jobId}`).expect(200);
    expect(jobAfter.body.applicationCount).toBe(1);
    expect(jobAfter.body.contactedCount).toBe(1);
    expect(jobAfter.body.interviewCount).toBe(1);
    expect(jobAfter.body.hiredCount).toBe(1);
  });

  it('closes the job posting', async () => {
    const res = await request(app.getHttpServer())
      .post(`/api/v1/jobs/${jobId}/close`)
      .set('Authorization', `Bearer ${employerToken}`)
      .expect(201);
    expect(res.body.status).toBe('CLOSED');
  });
});
