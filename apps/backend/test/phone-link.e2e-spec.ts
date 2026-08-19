import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { CapturingSmsProvider } from './utils/capturing-sms.provider';
import { CapturingEmailProvider } from './utils/capturing-email.provider';
import { ensureBaseFixtures, uniquePhone, uniqueEmail } from './utils/fixtures';

// Đặc tả §3: đăng ký bằng email KHÔNG tự động verify phone. Ứng tuyển/đăng tuyển đòi hỏi phone
// đã verify - nếu chưa, backend trả 403 với message cố định 'PHONE_NOT_VERIFIED' để frontend mở
// luồng xác minh OTP (POST /auth/phone/link/request + /verify), tái dùng đúng SmsProvider/OtpCode
// hiện có (không tạo hạ tầng SMS mới, không gửi SMS lúc đăng ký).
describe('Phone verification gate for apply/post job - §3', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let sms: CapturingSmsProvider;
  let email: CapturingEmailProvider;

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    sms = built.sms;
    email = built.email;
  });

  afterAll(async () => {
    await app.close();
  });

  async function registerByEmail(addr: string) {
    await request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr }).expect(201);
    const code = email.getLastCode(addr);
    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email/verify')
      .send({ email: addr, code })
      .expect(201);
    return res.body.accessToken as string;
  }

  it('tài khoản đăng ký bằng email có isPhoneVerified=false mặc định', async () => {
    const addr = uniqueEmail('phone-gate-default');
    await registerByEmail(addr);
    const user = await prisma.user.findUnique({ where: { email: addr } });
    expect(user?.isPhoneVerified).toBe(false);
  });

  it('ứng tuyển khi phone chưa verified bị từ chối với message PHONE_NOT_VERIFIED', async () => {
    const { area, category } = await ensureBaseFixtures(prisma);
    const employerUser = await prisma.user.create({
      data: { phone: uniquePhone(3), roles: ['EMPLOYER'], isPhoneVerified: true },
    });
    const employer = await prisma.employerProfile.create({ data: { userId: employerUser.id, businessName: 'Test Biz' } });
    const location = await prisma.employerLocation.create({
      data: { employerId: employer.id, name: 'CS test', address: 'addr', cityId: area.cityId, areaId: area.id, latitude: 12.2, longitude: 109.1 },
    });
    const job = await prisma.job.create({
      data: {
        employerId: employer.id, employerLocationId: location.id, categoryId: category.id,
        cityId: area.cityId, areaId: area.id, latitude: 12.2, longitude: 109.1,
        title: 'Test job', headcount: 1, employmentType: 'PART_TIME', shifts: ['EVENING'],
        salaryMin: 25000, salaryMax: 30000, salaryUnit: 'HOUR', status: 'ACTIVE',
      },
    });

    const token = await registerByEmail(uniqueEmail('apply-blocked'));
    await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${token}`)
      .send({ fullName: 'Ứng viên Test' })
      .expect(200);

    const res = await request(app.getHttpServer())
      .post(`/api/v1/jobs/${job.id}/apply`)
      .set('Authorization', `Bearer ${token}`)
      .expect(403);
    expect(res.body.message).toBe('PHONE_NOT_VERIFIED');
  });

  it('đăng tuyển khi phone chưa verified bị từ chối với message PHONE_NOT_VERIFIED', async () => {
    const { area } = await ensureBaseFixtures(prisma);
    const token = await registerByEmail(uniqueEmail('post-job-blocked'));
    await request(app.getHttpServer())
      .patch('/api/v1/me/roles')
      .set('Authorization', `Bearer ${token}`)
      .send({ role: 'EMPLOYER' })
      .expect(200);
    await request(app.getHttpServer())
      .put('/api/v1/me/employer-profile')
      .set('Authorization', `Bearer ${token}`)
      .send({ businessName: 'Quán Test Email Register' })
      .expect(200);
    const locRes = await request(app.getHttpServer())
      .post('/api/v1/me/employer-profile/locations')
      .set('Authorization', `Bearer ${token}`)
      .send({ name: 'CS 1', address: 'addr', cityId: area.cityId, areaId: area.id, latitude: 12.2, longitude: 109.1 })
      .expect(201);

    const res = await request(app.getHttpServer())
      .post('/api/v1/jobs')
      .set('Authorization', `Bearer ${token}`)
      .send({
        employerLocationId: locRes.body.id,
        categoryId: (await ensureBaseFixtures(prisma)).category.id,
        title: 'Tin test', headcount: 1, employmentType: 'PART_TIME', shifts: ['EVENING'],
        salaryMin: 25000, salaryMax: 30000, salaryUnit: 'HOUR',
      })
      .expect(403);
    expect(res.body.message).toBe('PHONE_NOT_VERIFIED');
  });

  it('luồng xác minh phone đầy đủ: request OTP -> verify -> ứng tuyển thành công', async () => {
    const { area, category } = await ensureBaseFixtures(prisma);
    const employerUser = await prisma.user.create({
      data: { phone: uniquePhone(3), roles: ['EMPLOYER'], isPhoneVerified: true },
    });
    const employer = await prisma.employerProfile.create({ data: { userId: employerUser.id, businessName: 'Test Biz 2' } });
    const location = await prisma.employerLocation.create({
      data: { employerId: employer.id, name: 'CS test 2', address: 'addr', cityId: area.cityId, areaId: area.id, latitude: 12.2, longitude: 109.1 },
    });
    const job = await prisma.job.create({
      data: {
        employerId: employer.id, employerLocationId: location.id, categoryId: category.id,
        cityId: area.cityId, areaId: area.id, latitude: 12.2, longitude: 109.1,
        title: 'Test job 2', headcount: 1, employmentType: 'PART_TIME', shifts: ['EVENING'],
        salaryMin: 25000, salaryMax: 30000, salaryUnit: 'HOUR', status: 'ACTIVE',
      },
    });

    const token = await registerByEmail(uniqueEmail('apply-after-verify'));
    await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${token}`)
      .send({ fullName: 'Ứng viên B' })
      .expect(200);

    const phone = uniquePhone(4);
    await request(app.getHttpServer())
      .post('/api/v1/auth/phone/link/request')
      .set('Authorization', `Bearer ${token}`)
      .send({ phone })
      .expect(201);
    const code = sms.getLastCode(phone);

    const verifyRes = await request(app.getHttpServer())
      .post('/api/v1/auth/phone/link/verify')
      .set('Authorization', `Bearer ${token}`)
      .send({ phone, code })
      .expect(201);
    expect(verifyRes.body.isPhoneVerified).toBe(true);

    await request(app.getHttpServer())
      .post(`/api/v1/jobs/${job.id}/apply`)
      .set('Authorization', `Bearer ${token}`)
      .expect(201);
  });

  it('verify phone với OTP sai bị từ chối, đúng số lần thử tối đa', async () => {
    const token = await registerByEmail(uniqueEmail('verify-wrong'));
    const phone = uniquePhone(4);
    await request(app.getHttpServer())
      .post('/api/v1/auth/phone/link/request')
      .set('Authorization', `Bearer ${token}`)
      .send({ phone })
      .expect(201);

    await request(app.getHttpServer())
      .post('/api/v1/auth/phone/link/verify')
      .set('Authorization', `Bearer ${token}`)
      .send({ phone, code: '000000' })
      .expect(400);
  });

  it('verify OTP hết hạn bị từ chối', async () => {
    const token = await registerByEmail(uniqueEmail('verify-expired'));
    const phone = uniquePhone(4);
    await request(app.getHttpServer())
      .post('/api/v1/auth/phone/link/request')
      .set('Authorization', `Bearer ${token}`)
      .send({ phone })
      .expect(201);
    const code = sms.getLastCode(phone);

    await prisma.otpCode.updateMany({ where: { phone }, data: { expiresAt: new Date(Date.now() - 1000) } });

    await request(app.getHttpServer())
      .post('/api/v1/auth/phone/link/verify')
      .set('Authorization', `Bearer ${token}`)
      .send({ phone, code })
      .expect(400);
  });

  it('số điện thoại đã verified bởi 1 tài khoản khác thì không gắn được vào tài khoản này', async () => {
    const takenPhone = uniquePhone(4);
    await prisma.user.create({ data: { phone: takenPhone, isPhoneVerified: true, roles: ['JOB_SEEKER'] } });

    const token = await registerByEmail(uniqueEmail('phone-taken'));
    await request(app.getHttpServer())
      .post('/api/v1/auth/phone/link/request')
      .set('Authorization', `Bearer ${token}`)
      .send({ phone: takenPhone })
      .expect(409);
  });

  it('phone đã verified rồi thì các thao tác tiếp theo không cần verify lại (không bị chặn)', async () => {
    const { area, category } = await ensureBaseFixtures(prisma);
    const employerUser = await prisma.user.create({
      data: { phone: uniquePhone(3), roles: ['EMPLOYER'], isPhoneVerified: true },
    });
    const employer = await prisma.employerProfile.create({ data: { userId: employerUser.id, businessName: 'Test Biz 3' } });
    const location = await prisma.employerLocation.create({
      data: { employerId: employer.id, name: 'CS test 3', address: 'addr', cityId: area.cityId, areaId: area.id, latitude: 12.2, longitude: 109.1 },
    });
    const job1 = await prisma.job.create({
      data: {
        employerId: employer.id, employerLocationId: location.id, categoryId: category.id,
        cityId: area.cityId, areaId: area.id, latitude: 12.2, longitude: 109.1,
        title: 'Test job 3', headcount: 1, employmentType: 'PART_TIME', shifts: ['EVENING'],
        salaryMin: 25000, salaryMax: 30000, salaryUnit: 'HOUR', status: 'ACTIVE',
      },
    });
    const job2 = await prisma.job.create({
      data: {
        employerId: employer.id, employerLocationId: location.id, categoryId: category.id,
        cityId: area.cityId, areaId: area.id, latitude: 12.2, longitude: 109.1,
        title: 'Test job 4', headcount: 1, employmentType: 'PART_TIME', shifts: ['EVENING'],
        salaryMin: 25000, salaryMax: 30000, salaryUnit: 'HOUR', status: 'ACTIVE',
      },
    });

    const token = await registerByEmail(uniqueEmail('no-reverify'));
    await request(app.getHttpServer())
      .put('/api/v1/me/job-seeker-profile')
      .set('Authorization', `Bearer ${token}`)
      .send({ fullName: 'Ứng viên C' })
      .expect(200);

    const phone = uniquePhone(4);
    await request(app.getHttpServer()).post('/api/v1/auth/phone/link/request').set('Authorization', `Bearer ${token}`).send({ phone }).expect(201);
    const code = sms.getLastCode(phone);
    await request(app.getHttpServer()).post('/api/v1/auth/phone/link/verify').set('Authorization', `Bearer ${token}`).send({ phone, code }).expect(201);

    // Ứng tuyển tin thứ 1 - không cần gửi OTP lại.
    await request(app.getHttpServer()).post(`/api/v1/jobs/${job1.id}/apply`).set('Authorization', `Bearer ${token}`).expect(201);
    // Ứng tuyển tin thứ 2 - vẫn không cần gửi OTP lại, không có yêu cầu phone/link nào mới.
    await request(app.getHttpServer()).post(`/api/v1/jobs/${job2.id}/apply`).set('Authorization', `Bearer ${token}`).expect(201);
  });
});
