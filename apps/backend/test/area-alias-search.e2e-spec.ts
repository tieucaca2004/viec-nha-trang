import { INestApplication } from '@nestjs/common';
import request from 'supertest';
import { PrismaService } from '../src/prisma/prisma.service';
import { buildTestApp } from './utils/build-app';
import { ensureBaseFixtures } from './utils/fixtures';

// Phase F §3/§4/§8: GET /areas mở rộng thêm `search` (backward-compatible) + AreaAlias (địa danh
// cũ trỏ về đơn vị hành chính hiện hành). Suite này verify: search theo tên hiện hành, search
// theo alias cũ (có dấu và không dấu), area không có alias vẫn trả về (aliases: []), và hành vi
// cũ (GET /areas không có search) không đổi.
describe('GET /areas - search + old-name alias (Phase F)', () => {
  let app: INestApplication;
  let prisma: PrismaService;
  let cityId: string;
  let currentAreaId: string;

  beforeAll(async () => {
    const built = await buildTestApp();
    app = built.app;
    prisma = built.prisma;

    const { city } = await ensureBaseFixtures(prisma);
    cityId = city.id;

    const currentArea = await prisma.area.upsert({
      where: { cityId_slug: { cityId, slug: `bac-nha-trang-${Date.now()}` } },
      update: {},
      create: { cityId, name: 'Phường Bắc Nha Trang (test)', slug: `bac-nha-trang-${Date.now()}` },
    });
    currentAreaId = currentArea.id;

    await prisma.areaAlias.createMany({
      data: [
        { areaId: currentAreaId, name: 'Vĩnh Hải (test)', normalizedName: 'vinh hai (test)' },
        { areaId: currentAreaId, name: 'Vĩnh Phước (test)', normalizedName: 'vinh phuoc (test)' },
      ],
    });
  });

  afterAll(async () => {
    await app.close();
  });

  it('GET /areas without search returns existing shape plus an aliases field (backward-compatible)', async () => {
    const res = await request(app.getHttpServer()).get('/api/v1/areas').query({ cityId }).expect(200);
    const area = res.body.find((a: { id: string }) => a.id === currentAreaId);
    expect(area).toBeDefined();
    expect(area.name).toBe('Phường Bắc Nha Trang (test)');
    expect(Array.isArray(area.aliases)).toBe(true);
    expect(area.aliases).toEqual(expect.arrayContaining(['Vĩnh Hải (test)', 'Vĩnh Phước (test)']));
  });

  it('search by old locality name (with diacritics) resolves to the current administrative area', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/areas')
      .query({ cityId, search: 'Vĩnh Hải' })
      .expect(200);
    const ids: string[] = res.body.map((a: { id: string }) => a.id);
    expect(ids).toContain(currentAreaId);
    // Không được trả về alias như 1 area độc lập - luôn là area hiện hành.
    for (const area of res.body) {
      expect(area.id).not.toBe('vinh-hai-alias-should-not-exist');
    }
  });

  it('search by old locality name WITHOUT diacritics still matches (accent-insensitive)', async () => {
    const res = await request(app.getHttpServer()).get('/api/v1/areas').query({ cityId, search: 'vinh hai' }).expect(200);
    const ids: string[] = res.body.map((a: { id: string }) => a.id);
    expect(ids).toContain(currentAreaId);
  });

  it('search by current name still works directly', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/areas')
      .query({ cityId, search: 'Bắc Nha Trang' })
      .expect(200);
    const ids: string[] = res.body.map((a: { id: string }) => a.id);
    expect(ids).toContain(currentAreaId);
  });

  it('search with no match returns an empty array, not an error', async () => {
    const res = await request(app.getHttpServer())
      .get('/api/v1/areas')
      .query({ cityId, search: 'khong-ton-tai-xyz' })
      .expect(200);
    expect(res.body).toEqual([]);
  });

  it('area with no aliases still returns aliases: [] (no crash on null relation)', async () => {
    const { otherArea } = await ensureBaseFixtures(prisma);
    const res = await request(app.getHttpServer()).get('/api/v1/areas').query({ cityId }).expect(200);
    const area = res.body.find((a: { id: string }) => a.id === otherArea.id);
    expect(area).toBeDefined();
    expect(area.aliases).toEqual([]);
  });
});
