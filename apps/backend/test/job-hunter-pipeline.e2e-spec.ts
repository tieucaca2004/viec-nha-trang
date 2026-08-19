import { INestApplication } from '@nestjs/common';
import { PrismaService } from '../src/prisma/prisma.service';
import { JobHunterService } from '../src/job-hunter/job-hunter.service';
import { ManualCollector } from '../src/job-hunter/collectors/manual-collector';
import { buildTestApp } from './utils/build-app';
import { ensureBaseFixtures } from './utils/fixtures';

// Kiểm tra toàn bộ pipeline thật (đặc tả Phần 4/7/8/10) chạy qua Nest DI + DB thật, không mock -
// Collector (ManualCollector) -> Extractor -> Normalizer -> Deduplicator -> LocationFilter ->
// QualityScorer -> Publisher, xác nhận provenance/dedupe/date-normalization/location-filter
// hoạt động đúng end-to-end và KHÔNG làm hỏng job/employer thật đã có.
describe('JobHunter pipeline (foundation) - e2e', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let jobHunter: JobHunterService;

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;
    jobHunter = app.get(JobHunterService);
    await ensureBaseFixtures(prisma);
  });

  afterAll(async () => {
    await app.close();
  });

  it('import job hợp lệ trong phạm vi Nha Trang => publish thành Job thật với đầy đủ provenance', async () => {
    const collector = new ManualCollector('pipeline-test-source-1', [
      {
        sourceName: 'pipeline-test-source-1',
        sourceJobId: 'job-001',
        sourceUrl: 'https://example-source.test/jobs/job-001',
        title: 'Tuyển nhân viên Phục vụ nhà hàng ven biển',
        description: 'Mô tả công việc phục vụ nhà hàng đầy đủ, chi tiết ca làm việc và quyền lợi cho nhân viên mới.',
        companyName: 'Nhà hàng Test Biển Xanh',
        locationText: 'Vĩnh Hải, Nha Trang',
        salaryText: '6-8 triệu/tháng',
        publishedText: 'Đăng 2 ngày trước',
      },
    ]);

    const result = await jobHunter.runOnce(collector, new Date('2026-08-19T00:00:00.000Z'));

    expect(result.collected).toBe(1);
    expect(result.inScope).toBe(1);
    expect(result.outOfScope).toBe(0);
    expect(result.published).toBe(1);

    const job = await prisma.job.findFirst({ where: { sourceName: 'pipeline-test-source-1', sourceJobId: 'job-001' } });
    expect(job).not.toBeNull();
    expect(job!.sourceType).toBe('IMPORTED');
    expect(job!.sourceUrl).toBe('https://example-source.test/jobs/job-001'); // không được mất URL nguồn
    expect(job!.sourcePublishedAt?.toISOString().slice(0, 10)).toBe('2026-08-17');
    expect(job!.title).toContain('Phục vụ');
    expect(job!.status).toBe('ACTIVE'); // đủ chất lượng -> publish thẳng
  });

  it('job ngoài phạm vi Nha Trang/Khánh Hòa bị loại, KHÔNG tạo Job', async () => {
    const collector = new ManualCollector('pipeline-test-source-2', [
      {
        sourceName: 'pipeline-test-source-2',
        sourceJobId: 'job-002',
        title: 'Nhân viên văn phòng',
        locationText: 'Quận 1, TP. Hồ Chí Minh',
      },
    ]);

    const result = await jobHunter.runOnce(collector);
    expect(result.outOfScope).toBe(1);
    expect(result.published).toBe(0);

    const job = await prisma.job.findFirst({ where: { sourceName: 'pipeline-test-source-2' } });
    expect(job).toBeNull();
  });

  it('job không rõ ngày đăng => sourcePublishedAt null, KHÔNG tự bịa ngày', async () => {
    const collector = new ManualCollector('pipeline-test-source-3', [
      {
        sourceName: 'pipeline-test-source-3',
        sourceJobId: 'job-003',
        title: 'Nhân viên phục vụ quán cà phê',
        locationText: 'Lộc Thọ, Nha Trang',
        // Không có publishedText - nguồn không cung cấp ngày đăng.
      },
    ]);

    await jobHunter.runOnce(collector, new Date('2026-08-19T00:00:00.000Z'));

    const job = await prisma.job.findFirst({ where: { sourceName: 'pipeline-test-source-3' } });
    expect(job).not.toBeNull();
    expect(job!.sourcePublishedAt).toBeNull();
  });

  it('job chất lượng thấp (thiếu hầu hết thông tin) => PENDING_REVIEW, không publish thẳng ACTIVE', async () => {
    const collector = new ManualCollector('pipeline-test-source-4', [
      { sourceName: 'pipeline-test-source-4', sourceJobId: 'job-004', title: 'Tuyển gấp', locationText: 'Nha Trang' },
    ]);

    await jobHunter.runOnce(collector);

    const job = await prisma.job.findFirst({ where: { sourceName: 'pipeline-test-source-4' } });
    expect(job).not.toBeNull();
    expect(job!.status).toBe('PENDING_REVIEW');
  });

  it('2 job trùng nhau từ 2 nguồn khác nhau => chỉ publish 1 canonical Job (dedupe)', async () => {
    const rawJobShared = {
      title: 'Nhân viên Phục vụ khách sạn 5 sao Vĩnh Hải',
      description: 'Mô tả chi tiết công việc phục vụ khách sạn 5 sao khu vực Vĩnh Hải, ca làm linh hoạt, đãi ngộ tốt.',
      companyName: 'Khách sạn Test Vĩnh Hải',
      locationText: 'Vĩnh Hải, Nha Trang',
      salaryText: '8-10 triệu/tháng',
    };

    const collectorA = new ManualCollector('pipeline-dedupe-source-a', [
      { ...rawJobShared, sourceName: 'pipeline-dedupe-source-a', sourceJobId: 'dupe-a' },
    ]);
    const collectorB = new ManualCollector('pipeline-dedupe-source-b', [
      { ...rawJobShared, sourceName: 'pipeline-dedupe-source-b', sourceJobId: 'dupe-b' },
    ]);

    // Chạy chung 1 batch để Deduplicator thấy cả 2 job cùng lúc (dedupe trong-batch) - mô phỏng
    // đúng use case "1 tin xuất hiện từ nhiều nguồn phải gom được thành 1 canonical".
    const raw = [...(await collectorA.collect()), ...(await collectorB.collect())];
    const combinedCollector = new ManualCollector('combined', raw);
    const result = await jobHunter.runOnce(combinedCollector);

    expect(result.duplicateGroups).toBe(1);
    expect(result.duplicatesFound).toBe(1);
    expect(result.published).toBe(1);
  });
});
