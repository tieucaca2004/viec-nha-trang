import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { ensureBaseFixtures, uniquePhone } from './utils/fixtures';

// Sửa lỗi Critical #5 (FULL AUDIT): POST /reviews trước đây có thể bypass hoàn toàn kiểm tra
// "chỉ đánh giá sau khi HIRED" bằng cách không gửi applicationId. Suite này chứng minh: thiếu
// applicationId bị từ chối, application không tồn tại bị từ chối, application của người khác bị
// từ chối, application chưa HIRED bị từ chối, và chỉ application HIRED thật của đúng reviewer
// mới tạo được review.
describe('Reviews security (POST /reviews) - Critical fix #5', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  let employerToken: string;
  let seekerToken: string;
  let otherSeekerToken: string;
  let employerId: string;
  let hiredApplicationId: string;
  let newApplicationId: string;
  const employerPhone = uniquePhone(6);
  const seekerPhone = uniquePhone(6);
  const otherSeekerPhone = uniquePhone(6);

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
    const employerProfile = await request(app.getHttpServer())
      .put('/api/v1/me/employer-profile')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ businessName: 'Chủ tin - Reviews Test' })
      .expect(200);
    employerId = employerProfile.body.id;
    const locationRes = await request(app.getHttpServer())
      .post('/api/v1/me/employer-profile/locations')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ name: 'Cơ sở', address: '1 Test St', cityId: city.id, areaId: area.id, latitude: 12.26, longitude: 109.2 })
      .expect(201);

    async function createJob(title: string) {
      const res = await request(app.getHttpServer())
        .post('/api/v1/jobs')
        .set('Authorization', `Bearer ${employerToken}`)
        .send({
          employerLocationId: locationRes.body.id,
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
      return res.body.id as string;
    }

    seekerToken = await loginAndReturnToken(seekerPhone);
    await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${seekerToken}`)
      .send({ fullName: 'Ứng viên Reviews Test' })
      .expect(200);

    otherSeekerToken = await loginAndReturnToken(otherSeekerPhone);
    await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${otherSeekerToken}`)
      .send({ fullName: 'Ứng viên khác' })
      .expect(200);

    // Job 1: seeker ứng tuyển, employer đưa hết pipeline tới HIRED.
    const hiredJobId = await createJob('Tin đã tuyển - review test');
    const hiredApplyRes = await request(app.getHttpServer())
      .post(`/api/v1/jobs/${hiredJobId}/apply`)
      .set('Authorization', `Bearer ${seekerToken}`)
      .expect(201);
    hiredApplicationId = hiredApplyRes.body.id;
    for (const status of ['VIEWED', 'CONTACTED', 'INTERVIEW', 'HIRED']) {
      await request(app.getHttpServer())
        .patch(`/api/v1/applications/${hiredApplicationId}/status`)
        .set('Authorization', `Bearer ${employerToken}`)
        .send({ status })
        .expect(200);
    }

    // Job 2: seeker ứng tuyển nhưng vẫn đang NEW (chưa HIRED).
    const newJobId = await createJob('Tin còn mới - review test');
    const newApplyRes = await request(app.getHttpServer())
      .post(`/api/v1/jobs/${newJobId}/apply`)
      .set('Authorization', `Bearer ${seekerToken}`)
      .expect(201);
    newApplicationId = newApplyRes.body.id;
  });

  afterAll(async () => {
    await app.close();
  });

  it('rejects a review with no applicationId at all (bypass attempt) - 400', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/reviews')
      .set('Authorization', `Bearer ${seekerToken}`)
      .send({ reviewerType: 'JOB_SEEKER', rating: 5, comment: 'Không có applicationId' })
      .expect(400);
  });

  it('rejects a review for an application that does not exist - 404', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/reviews')
      .set('Authorization', `Bearer ${seekerToken}`)
      .send({ reviewerType: 'JOB_SEEKER', applicationId: 'does-not-exist', rating: 5 })
      .expect(404);
  });

  it("rejects a review for another seeker's application - 403", async () => {
    await request(app.getHttpServer())
      .post('/api/v1/reviews')
      .set('Authorization', `Bearer ${otherSeekerToken}`)
      .send({ reviewerType: 'JOB_SEEKER', applicationId: hiredApplicationId, rating: 5 })
      .expect(403);
  });

  it('rejects a review when the application is not HIRED yet - 400', async () => {
    await request(app.getHttpServer())
      .post('/api/v1/reviews')
      .set('Authorization', `Bearer ${seekerToken}`)
      .send({ reviewerType: 'JOB_SEEKER', applicationId: newApplicationId, rating: 5 })
      .expect(400);
  });

  it('creates a review when the application is HIRED and belongs to the reviewer, and updates employer rating', async () => {
    const res = await request(app.getHttpServer())
      .post('/api/v1/reviews')
      .set('Authorization', `Bearer ${seekerToken}`)
      .send({ reviewerType: 'JOB_SEEKER', applicationId: hiredApplicationId, rating: 4, comment: 'Chủ tốt' })
      .expect(201);

    expect(res.body.employerId).toBe(employerId);
    expect(res.body.rating).toBe(4);

    const list = await request(app.getHttpServer())
      .get('/api/v1/reviews')
      .query({ targetType: 'employer', targetId: employerId })
      .set('Authorization', `Bearer ${seekerToken}`)
      .expect(200);
    expect(list.body.some((r: { id: string }) => r.id === res.body.id)).toBe(true);

    const employerProfile = await prisma.employerProfile.findUniqueOrThrow({ where: { id: employerId } });
    expect(employerProfile.ratingCount).toBeGreaterThanOrEqual(1);
    expect(employerProfile.ratingAvg).toBeGreaterThan(0);
  });

  it('rejects an attempt to spoof employerId in the request body (not a whitelisted DTO field)', async () => {
    // employerId/jobSeekerId không còn là field hợp lệ của CreateReviewDto (service tự suy ra từ
    // application) - forbidNonWhitelisted:true khiến request bị từ chối thẳng thay vì âm thầm bỏ
    // qua field lạ, một lớp bảo vệ còn chặt hơn việc chỉ "bỏ qua và dùng giá trị suy ra".
    await request(app.getHttpServer())
      .post('/api/v1/reviews')
      .set('Authorization', `Bearer ${seekerToken}`)
      .send({
        reviewerType: 'JOB_SEEKER',
        applicationId: hiredApplicationId,
        employerId: 'some-unrelated-employer-id',
        rating: 3,
      })
      .expect(400);
  });
});
