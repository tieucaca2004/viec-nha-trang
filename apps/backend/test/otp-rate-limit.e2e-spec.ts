import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { CapturingEmailProvider } from './utils/capturing-email.provider';
import { uniqueEmail } from './utils/fixtures';

/**
 * Bug thật trên Beta APK c8c1798: tài khoản đã tồn tại bấm "GỬI MÃ ĐĂNG NHẬP" một lần và nhận
 * HTTP 429 "Bạn đã yêu cầu quá nhiều lần. Vui lòng chờ 15 giây rồi thử lại." dù còn hợp lệ.
 *
 * ROOT CAUSE đã xác định: `POST /auth/register/email/request` là route DÙNG CHUNG cho cả đăng ký
 * lẫn đăng nhập, giới hạn 3 request/60s THEO IP - vài lần bấm đăng ký/gửi lại mã trước đó đã tiêu
 * hết hạn mức của lần bấm đăng nhập kế tiếp.
 *
 * SỬA ĐÚNG NGUYÊN NHÂN (không chỉ vá đếm ngược ở mobile): tách thành 2 route + 2 throttle bucket
 * RIÊNG - `/auth/register/email/request|verify` (đăng ký) và `/auth/login/email/request|verify`
 * (đăng nhập) - xem auth.controller.ts. Suite này khoá lại đúng tính chất mới:
 * - O. Đăng ký và đăng nhập KHÔNG còn ăn chung 1 hạn mức: cạn hạn mức đăng ký vẫn đăng nhập được.
 * - N. Retry-After là số giây CÒN LẠI của cửa sổ 60s (không phải "độ dài throttle").
 * - Hạn mức vẫn tính theo IP (không theo email) trong TỪNG bucket.
 * - Verify có bucket riêng với request, không bị ảnh hưởng khi request bị chặn.
 *
 * .env.test nới mọi limit lên 1000 cho các suite khác; ở đây ép về giá trị production thật (3)
 * rồi dựng app bằng module registry sạch, vì auth.controller.ts đọc process.env lúc nạp module.
 */
describe('Rate limit OTP email - đăng ký và đăng nhập có bucket RIÊNG (sau khi tách route)', () => {
  let app: INestApplication;
  let email: CapturingEmailProvider;
  const prevRegisterLimit = process.env.EMAIL_VERIFICATION_REQUEST_THROTTLE_LIMIT;
  const prevLoginLimit = process.env.EMAIL_LOGIN_REQUEST_THROTTLE_LIMIT;

  beforeAll(async () => {
    process.env.EMAIL_VERIFICATION_REQUEST_THROTTLE_LIMIT = '3';
    process.env.EMAIL_LOGIN_REQUEST_THROTTLE_LIMIT = '3';
    jest.resetModules();
    // eslint-disable-next-line @typescript-eslint/no-var-requires
    const { buildTestApp } = require('./utils/build-app');
    const built = await buildTestApp();
    app = built.app;
    email = built.email;
  });

  afterAll(async () => {
    await app.close();
    const restore = (key: string, prev: string | undefined) => {
      if (prev === undefined) delete process.env[key];
      else process.env[key] = prev;
    };
    restore('EMAIL_VERIFICATION_REQUEST_THROTTLE_LIMIT', prevRegisterLimit);
    restore('EMAIL_LOGIN_REQUEST_THROTTLE_LIMIT', prevLoginLimit);
  });

  const requestRegisterCode = (addr: string) =>
    request(app.getHttpServer()).post('/api/v1/auth/register/email/request').send({ email: addr });
  const requestLoginCode = (addr: string) =>
    request(app.getHttpServer()).post('/api/v1/auth/login/email/request').send({ email: addr });

  it('W1. hạn mức đăng ký tính theo IP chứ KHÔNG theo email: 3 email khác nhau vẫn chỉ được 3 lần', async () => {
    for (let i = 0; i < 3; i += 1) {
      await requestRegisterCode(uniqueEmail(`w1-${i}`)).expect(201);
    }
    const blocked = await requestRegisterCode(uniqueEmail('w1-email-hoan-toan-moi')).expect(429);
    expect(blocked.body.message).toContain('Too Many Requests');
  });

  it('W2. Retry-After là số giây CÒN LẠI của cửa sổ 60s, luôn <= 60 và > 0', async () => {
    const blocked = await requestRegisterCode(uniqueEmail('w2')).expect(429);

    const retryAfter = Number(blocked.headers['retry-after']);
    expect(Number.isFinite(retryAfter)).toBe(true);
    expect(retryAfter).toBeGreaterThan(0);
    expect(retryAfter).toBeLessThanOrEqual(60);
  });

  it('W3. hết hạn mức ở route request KHÔNG làm hỏng route verify (bucket riêng)', async () => {
    // Vẫn đang bị chặn ở route đăng ký...
    await requestRegisterCode(uniqueEmail('w3')).expect(429);

    // ...nhưng route verify có hạn mức riêng nên vẫn trả lỗi nghiệp vụ bình thường (mã sai),
    // KHÔNG phải 429.
    const res = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email/verify')
      .send({ email: uniqueEmail('w3-verify'), code: '000000' });
    expect(res.status).not.toBe(429);
  });

  // ---------- O. ĐĂNG KÝ VÀ ĐĂNG NHẬP KHÔNG ĂN CHUNG BUCKET (fix chính của phase này) ----------

  it('O1. cạn hạn mức ĐĂNG KÝ (3/3) -> route ĐĂNG NHẬP vẫn còn nguyên hạn mức, KHÔNG bị 429', async () => {
    // W1-W3 phía trên đã tiêu vài request của bucket ĐĂNG KÝ trong cùng cửa sổ 60s/IP - chờ hết
    // cửa sổ để bắt đầu với hạn mức SẠCH, tránh dương tính giả do các test trước cộng dồn.
    await new Promise((resolve) => setTimeout(resolve, 61_000));

    // Tiêu hết 3 request của bucket ĐĂNG KÝ bằng nhiều email khác nhau.
    for (let i = 0; i < 3; i += 1) {
      await requestRegisterCode(uniqueEmail(`o1-register-${i}`)).expect(201);
    }
    await requestRegisterCode(uniqueEmail('o1-register-blocked')).expect(429);

    // Route ĐĂNG NHẬP là bucket khác - đúng kịch bản người dùng thật: thử đăng ký/gửi lại mã vài
    // lần rồi mở màn Đăng nhập - PHẢI gửi được request thật, không kế thừa 429 từ đăng ký.
    const loginRes = await requestLoginCode(uniqueEmail('o1-login-should-work')).expect(201);
    expect(loginRes.body.expiresInSeconds).toBeGreaterThan(0);
  }, 90_000);

  it('O2. cạn hạn mức ĐĂNG NHẬP (3/3) -> route ĐĂNG KÝ vẫn còn nguyên hạn mức (đối xứng ngược lại)', async () => {
    // O1 vừa để lại 4 request trong bucket ĐĂNG KÝ (cùng cửa sổ) - chờ sạch cả 2 bucket trước khi
    // đánh giá "route đăng ký vẫn còn nguyên hạn mức" ở bước cuối.
    await new Promise((resolve) => setTimeout(resolve, 61_000));

    for (let i = 0; i < 3; i += 1) {
      await requestLoginCode(uniqueEmail(`o2-login-${i}`)).expect(201);
    }
    await requestLoginCode(uniqueEmail('o2-login-blocked')).expect(429);

    const registerRes = await requestRegisterCode(uniqueEmail('o2-register-should-work')).expect(201);
    expect(registerRes.body.expiresInSeconds).toBeGreaterThan(0);
  }, 90_000);

  it('O3. TRONG hạn mức, tài khoản ĐÃ TỒN TẠI xin mã đăng nhập qua route login bình thường và đăng nhập được', async () => {
    // Cửa sổ throttle là 60s theo IP - chờ hết cửa sổ để đảm bảo cả 2 bucket đều sạch, mô phỏng
    // người dùng thật mở app sau khi 2 test trên đã tiêu hạn mức.
    await new Promise((resolve) => setTimeout(resolve, 61_000));

    const addr = uniqueEmail('o3-tai-khoan-cu');

    // Tạo tài khoản thật qua route đăng ký.
    await requestRegisterCode(addr).expect(201);
    const registerRes = await request(app.getHttpServer())
      .post('/api/v1/auth/register/email/verify')
      .send({ email: addr, code: email.getLastCode(addr) })
      .expect(201);
    expect(registerRes.body.accessToken).toBeTruthy();

    // Đúng kịch bản người dùng báo lỗi: email ĐÃ CÓ tài khoản, xin mã ĐĂNG NHẬP qua route login
    // riêng -> phải 201 ngay (còn nguyên hạn mức bucket login, chưa từng bị đăng ký tiêu tới).
    await requestLoginCode(addr).expect(201);
    const loginRes = await request(app.getHttpServer())
      .post('/api/v1/auth/login/email/verify')
      .send({ email: addr, code: email.getLastCode(addr) })
      .expect(201);
    expect(loginRes.body.accessToken).toBeTruthy();
  }, 90_000);
});
