import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { ensureBaseFixtures, uniquePhone } from './utils/fixtures';

// Sửa lỗi High #6 (FULL AUDIT): sortBy=salary trước đây sort SAU KHI đã phân trang ở DB (khi
// không có toạ độ GPS), nên trang 1 không thực sự chứa job lương cao nhất. Suite này tạo đủ
// nhiều job (nhiều hơn 1 trang) với lương khác nhau và chứng minh trang 1 luôn đúng thứ tự,
// cả khi có và không có toạ độ GPS.
describe('Job search sortBy=salary correctness - High fix #6', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  let employerToken: string;
  let cityId: string;
  let areaId: string;
  let categoryId: string;
  let employerLocationId: string;
  const employerPhone = uniquePhone(5);
  const salaries = [50000, 90000, 30000, 120000, 70000, 20000, 110000, 40000, 100000, 60000, 80000, 10000];

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    sms = built.sms;

    const { city, area } = await ensureBaseFixtures(prisma);
    cityId = city.id;
    areaId = area.id;

    // Danh mục RIÊNG (không dùng slug 'phuc-vu' chung của ensureBaseFixtures) - các file
    // e2e-spec khác cũng tạo job ACTIVE ở category đó, nếu dùng chung sẽ làm sai lệch kết quả
    // sort/phân trang của chính suite này (thứ tự chạy các file test không đảm bảo cố định).
    const category = await prisma.jobCategory.create({
      data: { name: 'Salary Sort Test Category', slug: `salary-sort-test-${Date.now()}` },
    });
    categoryId = category.id;

    await request(app.getHttpServer()).post('/api/v1/auth/otp/request').send({ phone: employerPhone }).expect(201);
    const code = sms.getLastCode(employerPhone);
    const loginRes = await request(app.getHttpServer())
      .post('/api/v1/auth/otp/verify')
      .send({ phone: employerPhone, code })
      .expect(201);
    employerToken = loginRes.body.accessToken;

    await request(app.getHttpServer())
      .patch('/api/v1/me/roles')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ role: 'EMPLOYER' })
      .expect(200);
    await request(app.getHttpServer())
      .put('/api/v1/me/employer-profile')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ businessName: 'Chủ tin - Salary Sort Test' })
      .expect(200);
    const locationRes = await request(app.getHttpServer())
      .post('/api/v1/me/employer-profile/locations')
      .set('Authorization', `Bearer ${employerToken}`)
      .send({ name: 'Cơ sở', address: '1 Test St', cityId, areaId, latitude: 12.26, longitude: 109.2 })
      .expect(201);
    employerLocationId = locationRes.body.id;

    // 12 job (> limit mặc định 20 không đủ để lộ bug cũ - dùng limit nhỏ trong query thay vào đó)
    // với lương ngẫu nhiên xen kẽ để test thứ tự thật, không phải thứ tự tạo (publishedAt).
    for (const salaryMax of salaries) {
      await request(app.getHttpServer())
        .post('/api/v1/jobs')
        .set('Authorization', `Bearer ${employerToken}`)
        .send({
          employerLocationId,
          categoryId,
          title: `Tin lương ${salaryMax}`,
          headcount: 1,
          employmentType: 'PART_TIME',
          shifts: ['EVENING'],
          salaryMin: Math.max(0, salaryMax - 5000),
          salaryMax,
          salaryUnit: 'HOUR',
        })
        .expect(201);
    }
  });

  afterAll(async () => {
    await app.close();
  });

  it('page 1 (no GPS coords) contains the highest-salary jobs first, in strict descending order', async () => {
    const pageSize = 5;
    const res = await request(app.getHttpServer())
      .get('/api/v1/jobs')
      .query({ categoryId, sortBy: 'salary', limit: pageSize, offset: 0 })
      .expect(200);

    const page1Salaries: number[] = res.body.data.map((j: { salaryMax: number }) => j.salaryMax);
    expect(page1Salaries).toHaveLength(pageSize);

    const expectedTop5 = [...salaries].sort((a, b) => b - a).slice(0, pageSize);
    expect(page1Salaries).toEqual(expectedTop5);

    for (let i = 1; i < page1Salaries.length; i += 1) {
      expect(page1Salaries[i]).toBeLessThanOrEqual(page1Salaries[i - 1]);
    }
  });

  it('page 2 (no GPS coords) continues in descending order from page 1, no overlap/gap', async () => {
    const pageSize = 5;
    const page1 = await request(app.getHttpServer())
      .get('/api/v1/jobs')
      .query({ categoryId, sortBy: 'salary', limit: pageSize, offset: 0 })
      .expect(200);
    const page2 = await request(app.getHttpServer())
      .get('/api/v1/jobs')
      .query({ categoryId, sortBy: 'salary', limit: pageSize, offset: pageSize })
      .expect(200);

    const sortedDesc = [...salaries].sort((a, b) => b - a);
    expect(page2.body.data.map((j: { salaryMax: number }) => j.salaryMax)).toEqual(
      sortedDesc.slice(pageSize, pageSize * 2),
    );
    expect(page1.body.meta.total).toBe(page2.body.meta.total);
  });

  it('page 1 (WITH GPS coords) also sorts by salary correctly, not by distance', async () => {
    const pageSize = 5;
    const res = await request(app.getHttpServer())
      .get('/api/v1/jobs')
      .query({ categoryId, sortBy: 'salary', limit: pageSize, offset: 0, latitude: 12.26, longitude: 109.2 })
      .expect(200);

    const page1Salaries: number[] = res.body.data.map((j: { salaryMax: number }) => j.salaryMax);
    const expectedTop5 = [...salaries].sort((a, b) => b - a).slice(0, pageSize);
    expect(page1Salaries).toEqual(expectedTop5);
  });
});
