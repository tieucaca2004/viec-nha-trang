import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { ensureBaseFixtures, uniquePhone } from './utils/fixtures';

// Security tests bắt buộc theo Phase 2 §7: RBAC, ownership server-side, IDOR, JWT, input validation,
// SQL injection cơ bản, và kiểm tra response KHÔNG leak dữ liệu nhạy cảm - không chỉ HTTP status.
describe('Security', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  let categoryId: string;
  let cityId: string;
  let areaId: string;

  let seekerToken: string;
  let employerAToken: string;
  let employerBToken: string;
  let employerAJobId: string;

  const seekerPhone = uniquePhone(4);
  const employerAPhone = uniquePhone(4);
  const employerBPhone = uniquePhone(4);

  async function loginAndGetToken(phone: string): Promise<string> {
    await request(app.getHttpServer()).post('/api/v1/auth/otp/request').send({ phone }).expect(201);
    const code = sms.getLastCode(phone);
    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/otp/verify')
      .send({ phone, code })
      .expect(201);
    return res.body.accessToken;
  }

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    sms = built.sms;

    const { city, area, category } = await ensureBaseFixtures(prisma);
    cityId = city.id;
    areaId = area.id;
    categoryId = category.id;

    seekerToken = await loginAndGetToken(seekerPhone);
    employerAToken = await loginAndGetToken(employerAPhone);
    employerBToken = await loginAndGetToken(employerBPhone);

    await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${seekerToken}`)
      .send({ fullName: 'Security Test Seeker' })
      .expect(200);

    for (const token of [employerAToken, employerBToken]) {
      await request(app.getHttpServer())
        .patch('/api/v1/me/roles')
        .set('Authorization', `Bearer ${token}`)
        .send({ role: 'EMPLOYER' })
        .expect(200);
    }

    await request(app.getHttpServer())
      .put('/api/v1/me/employer-profile')
      .set('Authorization', `Bearer ${employerAToken}`)
      .send({ businessName: 'Employer A' })
      .expect(200);
    await request(app.getHttpServer())
      .put('/api/v1/me/employer-profile')
      .set('Authorization', `Bearer ${employerBToken}`)
      .send({ businessName: 'Employer B' })
      .expect(200);

    const locationA = await request(app.getHttpServer())
      .post('/api/v1/me/employer-profile/locations')
      .set('Authorization', `Bearer ${employerAToken}`)
      .send({ name: 'A', address: 'A St', cityId, areaId, latitude: 12.2, longitude: 109.1 })
      .expect(201);

    const jobA = await request(app.getHttpServer())
      .post('/api/v1/jobs')
      .set('Authorization', `Bearer ${employerAToken}`)
      .send({
        employerLocationId: locationA.body.id,
        categoryId,
        title: 'Job của Employer A',
        headcount: 1,
        employmentType: 'PART_TIME',
        shifts: ['EVENING'],
        salaryMin: 25000,
        salaryMax: 30000,
        salaryUnit: 'HOUR',
      })
      .expect(201);
    employerAJobId = jobA.body.id;
  });

  afterAll(async () => {
    await app.close();
  });

  it('rejects unauthenticated requests with 401', async () => {
    await request(app.getHttpServer()).get('/api/v1/me').expect(401);
    await request(app.getHttpServer()).get('/api/v1/admin/dashboard').expect(401);
  });

  it('rejects an invalid/garbage JWT with 401', async () => {
    await request(app.getHttpServer())
      .get('/api/v1/me')
      .set('Authorization', 'Bearer this.is.not.a.valid.jwt')
      .expect(401);
  });

  it('rejects a syntactically valid but unsigned/forged JWT with 401', async () => {
    // header.payload.signature giả mạo - không được ký bằng JWT_ACCESS_SECRET thật.
    const forged =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJzdWIiOiJmb3JnZWQiLCJyb2xlcyI6WyJBRE1JTiJdfQ.invalidsignature';
    await request(app.getHttpServer()).get('/api/v1/admin/dashboard').set('Authorization', `Bearer ${forged}`).expect(401);
  });

  it('rejects a valid JWT missing the required role with 403 (not 401)', async () => {
    // seeker có JWT hợp lệ nhưng không có role ADMIN -> phải là 403, không phải 401.
    await request(app.getHttpServer())
      .get('/api/v1/admin/dashboard')
      .set('Authorization', `Bearer ${seekerToken}`)
      .expect(403);
  });

  it('prevents a job seeker without EMPLOYER role from posting a job', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/jobs')
      .set('Authorization', `Bearer ${seekerToken}`)
      .send({
        employerLocationId: 'irrelevant',
        categoryId,
        title: 'Should be forbidden',
        headcount: 1,
        employmentType: 'PART_TIME',
        shifts: ['EVENING'],
        salaryMin: 25000,
        salaryMax: 30000,
        salaryUnit: 'HOUR',
      })
      .expect(403);
  });

  it("prevents Employer B from editing/closing Employer A's job (server-side ownership check)", async () => {
    const before = await prisma.job.findUniqueOrThrow({ where: { id: employerAJobId } });

    await request(app.getHttpServer())
      .patch(`/api/v1/jobs/${employerAJobId}`)
      .set('Authorization', `Bearer ${employerBToken}`)
      .send({
        employerLocationId: before.employerLocationId,
        categoryId,
        title: 'Hijacked title',
        headcount: 1,
        employmentType: 'PART_TIME',
        shifts: ['EVENING'],
        salaryMin: 99999,
        salaryMax: 99999,
        salaryUnit: 'HOUR',
      })
      .expect(403);

    await request(app.getHttpServer())
      .post(`/api/v1/jobs/${employerAJobId}/close`)
      .set('Authorization', `Bearer ${employerBToken}`)
      .expect(403);

    // Xác nhận response 403 không làm thay đổi dữ liệu thật (không chỉ kiểm tra status code).
    const after = await prisma.job.findUniqueOrThrow({ where: { id: employerAJobId } });
    expect(after.title).toBe(before.title);
    expect(after.status).toBe(before.status);
    expect(after.salaryMin).toBe(before.salaryMin);
  });

  it("prevents Employer B from viewing Employer A's applicants (private data isolation)", async () => {
    const res = await request(app.getHttpServer())
      .get(`/api/v1/employer/jobs/${employerAJobId}/applications`)
      .set('Authorization', `Bearer ${employerBToken}`)
      .expect(403);
    // Response lỗi không được kèm theo bất kỳ dữ liệu ứng viên nào.
    expect(res.body.data).toBeUndefined();
  });

  it('prevents applying to the same job twice from creating duplicate applications', async () => {
    const first = await request(app.getHttpServer())
      .post(`/api/v1/jobs/${employerAJobId}/apply`)
      .set('Authorization', `Bearer ${seekerToken}`)
      .expect(201);

    const second = await request(app.getHttpServer())
      .post(`/api/v1/jobs/${employerAJobId}/apply`)
      .set('Authorization', `Bearer ${seekerToken}`)
      .expect(201);

    expect(second.body.id).toBe(first.body.id);

    const count = await prisma.application.count({
      where: { jobId: employerAJobId, jobSeeker: { user: { phone: seekerPhone } } },
    });
    expect(count).toBe(1);
  });

  it("prevents Employer B from changing status of Employer A's applications", async () => {
    const application = await prisma.application.findFirstOrThrow({ where: { jobId: employerAJobId } });

    await request(app.getHttpServer())
      .patch(`/api/v1/applications/${application.id}/status`)
      .set('Authorization', `Bearer ${employerBToken}`)
      .send({ status: 'HIRED' })
      .expect(403);

    const unchanged = await prisma.application.findUniqueOrThrow({ where: { id: application.id } });
    expect(unchanged.status).toBe('NEW');
  });

  it('validates input and rejects unknown/malformed fields with 400', async () => {
    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/otp/verify')
      .send({ phone: 'not-a-phone-number', code: '123456', unexpectedField: 'hack' })
      .expect(400);
    expect(res.body.statusCode).toBe(400);
  });

  it('is not vulnerable to a basic SQL injection payload in search', async () => {
    const before = await prisma.job.count();

    const res = await request(app.getHttpServer())
      .get('/api/v1/jobs')
      .query({ keyword: "'; DROP TABLE jobs; --" })
      .expect(200);

    expect(Array.isArray(res.body.data)).toBe(true);

    const after = await prisma.job.count();
    expect(after).toBe(before);
  });

  it('does not leak passwordHash in any user-facing response', async () => {
    const me = await request(app.getHttpServer())
      .get('/api/v1/me')
      .set('Authorization', `Bearer ${seekerToken}`)
      .expect(200);
    expect(me.body).not.toHaveProperty('passwordHash');

    // Tạo 1 admin để kiểm tra danh sách users của admin cũng không leak passwordHash.
    const adminPhone = uniquePhone(4);
    await prisma.user.create({ data: { phone: adminPhone, roles: ['ADMIN'], isPhoneVerified: true } });
    const adminToken = await loginAndGetToken(adminPhone);

    const usersList = await request(app.getHttpServer())
      .get('/api/v1/admin/users')
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);
    for (const user of usersList.body) {
      expect(user).not.toHaveProperty('passwordHash');
    }
  });
});
