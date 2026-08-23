import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { ensureBaseFixtures, uniquePhone } from './utils/fixtures';

// Phase F §9: xác nhận Haversine/radiusKm/distanceKm hiện có (JobsService.findMany, đã LOCKED)
// vẫn đúng sau khi thêm AreaAlias - không đổi hành vi filter/sort đã có, chỉ verify.
// Đặt job dọc theo đúng 1 kinh tuyến (cùng longitude với điểm tham chiếu) - với dLon=0, công
// thức haversine rút gọn CHÍNH XÁC còn distance = R * dLat(rad), không xấp xỉ, nên có thể tạo
// job ở khoảng cách biết trước với sai số cực nhỏ (đủ để assert exact-boundary).
const EARTH_RADIUS_KM = 6371;
function latOffsetDegForKm(km: number): number {
  return (km / EARTH_RADIUS_KM) * (180 / Math.PI);
}

describe('Job radius search (Haversine) - Phase F regression verification', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  let employerToken: string;
  let cityId: string;
  let areaId: string;
  let categoryId: string;
  let employerLocationId: string;
  const employerPhone = uniquePhone();

  const originLat = 12.0;
  const originLng = 109.0;
  // Khoảng cách chính xác (km) từng job cách điểm tham chiếu (originLat, originLng).
  const distancesKm = [1, 5, 10, 10.1, 20, 31];
  const jobIdByDistance: Record<number, string> = {};

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    sms = built.sms;

    const { city, area } = await ensureBaseFixtures(prisma);
    cityId = city.id;
    areaId = area.id;

    const category = await prisma.jobCategory.create({
      data: { name: 'Radius Test Category', slug: `radius-test-${Date.now()}` },
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
      .send({ businessName: 'Chủ tin - Radius Test' })
      .expect(200);

    for (const km of distancesKm) {
      const lat = originLat + latOffsetDegForKm(km);
      const locationRes = await request(app.getHttpServer())
        .post('/api/v1/me/employer-profile/locations')
        .set('Authorization', `Bearer ${employerToken}`)
        .send({ name: `Cơ sở ${km}km`, address: '1 Test St', cityId, areaId, latitude: lat, longitude: originLng })
        .expect(201);
      employerLocationId = locationRes.body.id;

      const jobRes = await request(app.getHttpServer())
        .post('/api/v1/jobs')
        .set('Authorization', `Bearer ${employerToken}`)
        .send({
          employerLocationId,
          categoryId,
          title: `Tin cách ${km}km`,
          headcount: 1,
          employmentType: 'PART_TIME',
          shifts: ['EVENING'],
          salaryMin: 20000,
          salaryMax: 30000,
          salaryUnit: 'HOUR',
        })
        .expect(201);
      jobIdByDistance[km] = jobRes.body.id;
    }
  });

  afterAll(async () => {
    await app.close();
  });

  it('distanceKm returned by API matches real Haversine distance for each job (within 0.05km)', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/jobs')
      .query({ categoryId, latitude: originLat, longitude: originLng, limit: 50 })
      .expect(200);

    for (const km of distancesKm) {
      const job = res.body.data.find((j: { id: string }) => j.id === jobIdByDistance[km]);
      expect(job).toBeDefined();
      expect(job.distanceKm).toBeCloseTo(km, 1);
    }
  });

  it('radiusKm=10 includes jobs <= 10km and excludes jobs > 10km (exact boundary)', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/jobs')
      .query({ categoryId, latitude: originLat, longitude: originLng, radiusKm: 10, limit: 50 })
      .expect(200);

    const returnedIds: string[] = res.body.data.map((j: { id: string }) => j.id);
    expect(returnedIds).toContain(jobIdByDistance[1]);
    expect(returnedIds).toContain(jobIdByDistance[5]);
    expect(returnedIds).toContain(jobIdByDistance[10]);
    expect(returnedIds).not.toContain(jobIdByDistance[10.1]);
    expect(returnedIds).not.toContain(jobIdByDistance[20]);
    expect(returnedIds).not.toContain(jobIdByDistance[31]);
  });

  it('radiusKm=25 includes the 20km job that radiusKm=10 excluded', async () => {
    // Dùng radiusKm=25 (không phải =20) để có biên độ an toàn khỏi sai số float của
    // sin/atan2 khi query radius trùng khít với khoảng cách thật của job - test biên chính xác
    // (distance đúng bằng radius) đã được test "radiusKm=10 ... (exact boundary)" ở trên phủ
    // đúng nghĩa (job 10km nằm trong, job 10.1km - có biên độ 0.1km - nằm ngoài).
    const res = await request(app.getHttpServer())
      .get('/api/v1/jobs')
      .query({ categoryId, latitude: originLat, longitude: originLng, radiusKm: 25, limit: 50 })
      .expect(200);

    const returnedIds: string[] = res.body.data.map((j: { id: string }) => j.id);
    expect(returnedIds).toContain(jobIdByDistance[20]);
    expect(returnedIds).not.toContain(jobIdByDistance[31]);
  });

  it('without radiusKm, all jobs (including 31km) are returned, sorted nearest-first by distance', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/jobs')
      .query({ categoryId, latitude: originLat, longitude: originLng, limit: 50 })
      .expect(200);

    const returnedIds: string[] = res.body.data.map((j: { id: string }) => j.id);
    expect(returnedIds).toContain(jobIdByDistance[31]);

    const ourJobDistances = res.body.data
      .filter((j: { id: string }) => Object.values(jobIdByDistance).includes(j.id))
      .map((j: { distanceKm: number }) => j.distanceKm);
    for (let i = 1; i < ourJobDistances.length; i += 1) {
      expect(ourJobDistances[i]).toBeGreaterThanOrEqual(ourJobDistances[i - 1]);
    }
  });

  it('without latitude/longitude, jobs are returned with distanceKm=null (no coordinate crash)', async () => {
    const res = await request(app.getHttpServer()).get('/api/v1/jobs').query({ categoryId, limit: 50 }).expect(200);

    const job = res.body.data.find((j: { id: string }) => j.id === jobIdByDistance[1]);
    expect(job).toBeDefined();
    expect(job.distanceKm).toBeNull();
  });
});
