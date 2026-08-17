import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { JobStatus } from '@prisma/client';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { ensureBaseFixtures, uniquePhone } from './utils/fixtures';

// Sửa lỗi Critical #4 (FULL AUDIT): GET /jobs/:id trước đây trả về job bất kể status, và tăng
// viewCount kể cả khi chính chủ tự xem. Suite này chứng minh: chỉ job ACTIVE mới public; job
// DRAFT/CLOSED/EXPIRED chỉ owner/admin xem được; viewCount không tăng khi owner tự xem.
describe('Job visibility (GET /jobs/:id) - Critical fix #4', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  let employerToken: string;
  let otherEmployerToken: string;
  let adminToken: string;
  let jobId: string;
  const employerPhone = uniquePhone(9);
  const otherEmployerPhone = uniquePhone(9);
  const adminPhone = uniquePhone(9);

  async function loginAndReturnToken(phone: string): Promise<string> {
    await request(app.getHttpServer()).post('/api/v1/auth/otp/request').send({ phone }).expect(201);
    const code = sms.getLastCode(phone);
    const res = await request(app.getHttpServer()).post('/api/v1/auth/otp/verify').send({ phone, code }).expect(201);
    return res.body.accessToken;
  }

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    sms = built.sms;

    const { city, area, category } = await ensureBaseFixtures(prisma);

    employerToken = await loginAndReturnToken(employerPhone);
    await request(app.getHttpServer())
      .patch('/api/v1/me/roles')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ role: 'EMPLOYER' })
      .expect(200);
    await request(app.getHttpServer())
      .put('/api/v1/me/employer-profile')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ businessName: 'Chủ tin - Job Visibility Test' })
      .expect(200);
    const locationRes = await request(app.getHttpServer())
      .post('/api/v1/me/employer-profile/locations')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ name: 'Cơ sở', address: '1 Test St', cityId: city.id, areaId: area.id, latitude: 12.26, longitude: 109.2 })
      .expect(201);

    const jobRes = await request(app.getHttpServer())
      .post('/api/v1/jobs')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({
        employerLocationId: locationRes.body.id,
        categoryId: category.id,
        title: 'Tin test hiển thị',
        headcount: 1,
        employmentType: 'PART_TIME',
        shifts: ['EVENING'],
        salaryMin: 20000,
        salaryMax: 25000,
        salaryUnit: 'HOUR',
      })
      .expect(201);
    jobId = jobRes.body.id;

    otherEmployerToken = await loginAndReturnToken(otherEmployerPhone);
    await request(app.getHttpServer())
      .patch('/api/v1/me/roles')
      .set('Authorization', `Bearer ${otherEmployerToken}`)
      .send({ role: 'EMPLOYER' })
      .expect(200);

    await prisma.user.create({ data: { phone: adminPhone, roles: ['ADMIN'], isPhoneVerified: true } });
    adminToken = await loginAndReturnToken(adminPhone);
  });

  afterAll(async () => {
    await app.close();
  });

  it('publicly exposes an ACTIVE job to anonymous callers and increments viewCount', async () => {
    const before = await request(app.getHttpServer()).get(`/api/v1/jobs/${jobId}`).expect(200);
    const viewsBefore = before.body.viewCount;

    const res = await request(app.getHttpServer()).get(`/api/v1/jobs/${jobId}`).expect(200);
    expect(res.body.status).toBe('ACTIVE');
    expect(res.body.viewCount).toBe(viewsBefore + 1);
  });

  it.each<JobStatus>(['DRAFT', 'CLOSED', 'EXPIRED'])('hides a %s job from anonymous callers (404)', async (status) => {
    await prisma.job.update({ where: { id: jobId }, data: { status } });
    await request(app.getHttpServer()).get(`/api/v1/jobs/${jobId}`).expect(404);
    await prisma.job.update({ where: { id: jobId }, data: { status: 'ACTIVE' } });
  });

  it.each<JobStatus>(['DRAFT', 'CLOSED', 'EXPIRED'])('hides a %s job from an unrelated logged-in employer (404)', async (status) => {
    await prisma.job.update({ where: { id: jobId }, data: { status } });
    await request(app.getHttpServer())
      .get(`/api/v1/jobs/${jobId}`)
      .set('Authorization', `Bearer ${otherEmployerToken}`)
      .expect(404);
    await prisma.job.update({ where: { id: jobId }, data: { status: 'ACTIVE' } });
  });

  it('lets the owning employer view their own non-ACTIVE job', async () => {
    await prisma.job.update({ where: { id: jobId }, data: { status: 'CLOSED' } });
    const res = await request(app.getHttpServer())
      .get(`/api/v1/jobs/${jobId}`)
      .set('Authorization', `Bearer ${employerToken}`)
      .expect(200);
    expect(res.body.status).toBe('CLOSED');
    await prisma.job.update({ where: { id: jobId }, data: { status: 'ACTIVE' } });
  });

  it('lets an ADMIN view a non-ACTIVE job that is not theirs', async () => {
    await prisma.job.update({ where: { id: jobId }, data: { status: 'DRAFT' } });
    const res = await request(app.getHttpServer())
      .get(`/api/v1/jobs/${jobId}`)
      .set('Authorization', `Bearer ${adminToken}`)
      .expect(200);
    expect(res.body.status).toBe('DRAFT');
    await prisma.job.update({ where: { id: jobId }, data: { status: 'ACTIVE' } });
  });

  it('does not increment viewCount when the owner views their own job', async () => {
    const before = await prisma.job.findUniqueOrThrow({ where: { id: jobId } });

    await request(app.getHttpServer())
      .get(`/api/v1/jobs/${jobId}`)
      .set('Authorization', `Bearer ${employerToken}`)
      .expect(200);
    await request(app.getHttpServer())
      .get(`/api/v1/jobs/${jobId}`)
      .set('Authorization', `Bearer ${employerToken}`)
      .expect(200);

    const after = await prisma.job.findUniqueOrThrow({ where: { id: jobId } });
    expect(after.viewCount).toBe(before.viewCount);
  });

  it('does increment viewCount when a non-owner (including another employer) views the job', async () => {
    const before = await prisma.job.findUniqueOrThrow({ where: { id: jobId } });

    await request(app.getHttpServer())
      .get(`/api/v1/jobs/${jobId}`)
      .set('Authorization', `Bearer ${otherEmployerToken}`)
      .expect(200);

    const after = await prisma.job.findUniqueOrThrow({ where: { id: jobId } });
    expect(after.viewCount).toBe(before.viewCount + 1);
  });
});
