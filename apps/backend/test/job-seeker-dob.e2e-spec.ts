import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { uniquePhone } from './utils/fixtures';

// Đặc tả §2 phase kế tiếp: dateOfBirth trên JobSeekerProfile - valid date được lưu/đọc lại
// đúng, ngày tương lai bị từ chối.
describe('Job seeker dateOfBirth - §2', () => {
  let app: INestApplication;
  let sms: CapturingSmsProvider;

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    sms = built.sms;
  });

  afterAll(async () => {
    await app.close();
  });

  async function login(phone: string) {
    await request(app.getHttpServer()).post('/api/v1/auth/otp/request').send({ phone }).expect(201);
    const code = sms.getLastCode(phone);
    const res = await request(app.getHttpServer()).post('/api/v1/auth/otp/verify').send({ phone, code }).expect(201);
    return res.body.accessToken as string;
  }

  it('lưu và đọc lại đúng ngày sinh hợp lệ', async () => {
    const token = await login(uniquePhone(2));

    await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${token}`)
      .send({ fullName: 'Nguyễn Văn A', dateOfBirth: '2000-05-15' })
      .expect(200);

    const res = await request(app.getHttpServer())
      .get('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${token}`)
      .expect(200);

    expect(new Date(res.body.dateOfBirth).toISOString().slice(0, 10)).toBe('2000-05-15');
  });

  it('từ chối ngày sinh ở tương lai', async () => {
    const token = await login(uniquePhone(2));
    const futureDate = new Date(Date.now() + 365 * 24 * 60 * 60 * 1000).toISOString().slice(0, 10);

    await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${token}`)
      .send({ fullName: 'Nguyễn Văn B', dateOfBirth: futureDate })
      .expect(400);
  });

  it('không có dateOfBirth vẫn lưu hồ sơ bình thường (trường optional)', async () => {
    const token = await login(uniquePhone(2));

    await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${token}`)
      .send({ fullName: 'Nguyễn Văn C' })
      .expect(200);
  });
});
