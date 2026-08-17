// Load test cho VIỆC NHA TRANG backend - đặc tả docs/PLAN.md §11, docs/LOAD_TESTING.md.
// Chạy: k6 run -e BASE_URL=... -e VUS=100 -e DURATION=2m loadtest/scenarios.js
//
// YÊU CẦU MÔI TRƯỜNG TRƯỚC KHI CHẠY (không chạy nhắm vào production thật):
//   - SMS_PROVIDER=console (để dùng được /auth/otp/debug/:phone)
//   - NODE_ENV != production (route debug OTP tự trả 404 nếu NODE_ENV=production)
//   - OTP_REQUEST_THROTTLE_LIMIT / OTP_VERIFY_THROTTLE_LIMIT đặt cao (setup() gọi OTP nhiều lần
//     liên tiếp từ cùng 1 IP của máy chạy k6)
import http from 'k6/http';
import { check, sleep } from 'k6';
import { Counter, Trend } from 'k6/metrics';

const BASE_URL = __ENV.BASE_URL || 'http://localhost:3000/api/v1';
const SEEKER_POOL_SIZE = Number(__ENV.SEEKER_POOL_SIZE || 20);

export const options = {
  scenarios: {
    main: {
      executor: 'ramping-vus',
      startVUs: 0,
      stages: [
        { duration: '30s', target: Number(__ENV.VUS || 50) },
        { duration: __ENV.DURATION || '2m', target: Number(__ENV.VUS || 50) },
        { duration: '30s', target: 0 },
      ],
    },
  },
  thresholds: {
    http_req_duration: ['p(95)<800', 'p(99)<1500'],
    http_req_failed: ['rate<0.02'],
  },
};

const applyErrors = new Counter('viec_apply_errors');
const searchLatency = new Trend('viec_search_latency');

function jsonHeaders(token) {
  return { headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) } };
}

function otpLogin(phonePrefix) {
  const phone = `09${phonePrefix}${String(Math.floor(Math.random() * 9999999)).padStart(7, '0')}`.slice(0, 10);
  http.post(`${BASE_URL}/auth/otp/request`, JSON.stringify({ phone }), jsonHeaders());
  const debugRes = http.get(`${BASE_URL}/auth/otp/debug/${phone}`);
  if (debugRes.status !== 200) {
    throw new Error(`Không lấy được OTP debug cho ${phone} - kiểm tra SMS_PROVIDER=console và NODE_ENV != production trên môi trường target.`);
  }
  const code = JSON.parse(debugRes.body).code;
  const verifyRes = http.post(`${BASE_URL}/auth/otp/verify`, JSON.stringify({ phone, code }), jsonHeaders());
  check(verifyRes, { 'otp verify 201': (r) => r.status === 201 });
  return { phone, token: JSON.parse(verifyRes.body).accessToken };
}

// setup() chạy 1 lần trước khi tăng VU - chuẩn bị 1 employer + N job seeker + dữ liệu nền,
// tránh mỗi VU iteration phải xin OTP riêng (OTP bị rate-limit theo IP, xem đầu file).
export function setup() {
  const categoriesRes = http.get(`${BASE_URL}/categories`);
  const areasRes = http.get(`${BASE_URL}/areas`);
  const citiesRes = http.get(`${BASE_URL}/cities`);
  const categoryId = JSON.parse(categoriesRes.body)[0].id;
  const areaId = JSON.parse(areasRes.body)[0].id;
  const cityId = JSON.parse(citiesRes.body)[0].id;

  const employer = otpLogin('81');
  http.patch(`${BASE_URL}/me/roles`, JSON.stringify({ role: 'EMPLOYER' }), jsonHeaders(employer.token));
  http.put(`${BASE_URL}/me/employer-profile`, JSON.stringify({ businessName: 'Load Test Co' }), jsonHeaders(employer.token));
  const locationRes = http.post(
    `${BASE_URL}/me/employer-profile/locations`,
    JSON.stringify({ name: 'Load Test Location', address: 'Load test', cityId, areaId, latitude: 12.24, longitude: 109.19 }),
    jsonHeaders(employer.token),
  );
  const employerLocationId = JSON.parse(locationRes.body).id;

  const jobRes = http.post(
    `${BASE_URL}/jobs`,
    JSON.stringify({
      employerLocationId,
      categoryId,
      title: 'Load test job',
      headcount: 5,
      employmentType: 'PART_TIME',
      shifts: ['EVENING'],
      salaryMin: 25000,
      salaryMax: 30000,
      salaryUnit: 'HOUR',
    }),
    jsonHeaders(employer.token),
  );
  const jobId = JSON.parse(jobRes.body).id;

  const seekers = [];
  for (let i = 0; i < SEEKER_POOL_SIZE; i++) {
    const seeker = otpLogin('82');
    http.put(`${BASE_URL}/me/job-seeker-profile`, JSON.stringify({ fullName: `Load Test Seeker ${i}` }), jsonHeaders(seeker.token));
    seekers.push(seeker.token);
  }

  return { employerToken: employer.token, seekerTokens: seekers, jobId, categoryId, areaId, employerLocationId };
}

function randomSeekerToken(data) {
  return data.seekerTokens[Math.floor(Math.random() * data.seekerTokens.length)];
}

// Mỗi VU iteration chọn ngẫu nhiên 1 trong các kịch bản theo trọng số gần với hành vi thật:
// đọc (search/filter/detail) nhiều hơn hẳn ghi (apply/save/create job).
export default function (data) {
  const r = Math.random();

  if (r < 0.30) {
    // 1. Search jobs
    const res = http.get(`${BASE_URL}/jobs?keyword=Load`, jsonHeaders());
    searchLatency.add(res.timings.duration);
    check(res, { 'search 200': (r) => r.status === 200 });
  } else if (r < 0.50) {
    // 2. Filter jobs
    const res = http.get(`${BASE_URL}/jobs?categoryId=${data.categoryId}&areaId=${data.areaId}&employmentType=PART_TIME`, jsonHeaders());
    check(res, { 'filter 200': (r) => r.status === 200 });
  } else if (r < 0.68) {
    // 3. Job detail
    const res = http.get(`${BASE_URL}/jobs/${data.jobId}`, jsonHeaders());
    check(res, { 'detail 200': (r) => r.status === 200 });
  } else if (r < 0.80) {
    // 4. Apply to job (one-tap application, mục 21)
    const token = randomSeekerToken(data);
    const res = http.post(`${BASE_URL}/jobs/${data.jobId}/apply`, null, jsonHeaders(token));
    if (res.status !== 201) applyErrors.add(1);
    check(res, { 'apply 201': (r) => r.status === 201 });
  } else if (r < 0.88) {
    // 5. Save job
    const token = randomSeekerToken(data);
    const res = http.post(`${BASE_URL}/saved-jobs/${data.jobId}`, null, jsonHeaders(token));
    check(res, { 'save 201': (r) => r.status === 201 });
  } else if (r < 0.93) {
    // 6. Employer reads applicants
    const res = http.get(`${BASE_URL}/employer/jobs/${data.jobId}/applications`, jsonHeaders(data.employerToken));
    check(res, { 'applicants 200': (r) => r.status === 200 });
  } else if (r < 0.97) {
    // 7. Job seeker checks notifications
    const token = randomSeekerToken(data);
    const res = http.get(`${BASE_URL}/notifications`, jsonHeaders(token));
    check(res, { 'notifications 200': (r) => r.status === 200 });
  } else {
    // 8. Employer creates a new job posting (thấp nhất trong tỉ trọng - ghi tốn kém nhất)
    const res = http.post(
      `${BASE_URL}/jobs`,
      JSON.stringify({
        employerLocationId: data.employerLocationId,
        categoryId: data.categoryId,
        title: `Load test job ${Date.now()}`,
        headcount: 1,
        employmentType: 'PART_TIME',
        shifts: ['MORNING'],
        salaryMin: 20000,
        salaryMax: 25000,
        salaryUnit: 'HOUR',
      }),
      jsonHeaders(data.employerToken),
    );
    check(res, { 'create job 201': (r) => r.status === 201 });
  }

  sleep(Math.random() * 1.5 + 0.5); // mô phỏng "think time" giữa các thao tác của người dùng thật
}
