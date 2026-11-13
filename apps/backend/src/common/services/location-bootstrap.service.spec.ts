import { LocationBootstrapService } from './location-bootstrap.service';
import { PrismaService } from '../../prisma/prisma.service';

// Fake Prisma tối thiểu, mô phỏng đúng ngữ nghĩa upsert (match where -> áp update, không match ->
// tạo bằng create) để test được hành vi thật trên dữ liệu, không chỉ kiểm tra tham số gọi hàm.
function createFakePrisma() {
  const cities = new Map<string, any>();
  const areas = new Map<string, any>();

  return {
    city: {
      upsert: jest.fn(async ({ where, update, create }: any) => {
        const existing = cities.get(where.slug);
        if (existing) {
          Object.assign(existing, update);
          return existing;
        }
        const created = { id: `city-${where.slug}`, ...create };
        cities.set(where.slug, created);
        return created;
      }),
    },
    area: {
      upsert: jest.fn(async ({ where, update, create }: any) => {
        const key = `${where.cityId_slug.cityId}:${where.cityId_slug.slug}`;
        const existing = areas.get(key);
        if (existing) {
          Object.assign(existing, update);
          return existing;
        }
        const created = { id: `area-${key}`, ...create };
        areas.set(key, created);
        return created;
      }),
    },
    __areas: areas,
    __cities: cities,
  } as unknown as PrismaService & { __areas: Map<string, any>; __cities: Map<string, any> };
}

describe('LocationBootstrapService (đặc tả: bootstrap City/Area Nha Trang, không ghi đè dữ liệu Admin)', () => {
  const ORIGINAL_ENV = process.env.NODE_ENV;

  beforeEach(() => {
    process.env.NODE_ENV = 'production';
  });

  afterEach(() => {
    process.env.NODE_ENV = ORIGINAL_ENV;
  });

  it('tạo mới Area khi chưa tồn tại (isActive=true)', async () => {
    const prisma = createFakePrisma();
    const service = new LocationBootstrapService(prisma);

    await service.onModuleInit();

    const created = prisma.__areas.get(`city-nha-trang:loc-tho`);
    expect(created).toBeDefined();
    expect(created.isActive).toBe(true);
    expect(created.name).toBe('Lộc Thọ');
  });

  it('Area đã tồn tại với isActive=false vẫn giữ false sau bootstrap', async () => {
    const prisma = createFakePrisma();
    prisma.__cities.set('nha-trang', { id: 'city-nha-trang', name: 'Nha Trang', slug: 'nha-trang', isActive: true });
    prisma.__areas.set('city-nha-trang:loc-tho', {
      id: 'area-city-nha-trang:loc-tho',
      cityId: 'city-nha-trang',
      name: 'Lộc Thọ (đã đổi tên bởi Admin)',
      slug: 'loc-tho',
      isActive: false,
    });
    const service = new LocationBootstrapService(prisma);

    await service.onModuleInit();

    const area = prisma.__areas.get('city-nha-trang:loc-tho');
    expect(area.isActive).toBe(false);
    expect(area.name).toBe('Lộc Thọ (đã đổi tên bởi Admin)');
  });

  it('Area đã tồn tại với isActive=true vẫn giữ true sau bootstrap', async () => {
    const prisma = createFakePrisma();
    prisma.__cities.set('nha-trang', { id: 'city-nha-trang', name: 'Nha Trang', slug: 'nha-trang', isActive: true });
    prisma.__areas.set('city-nha-trang:loc-tho', {
      id: 'area-city-nha-trang:loc-tho',
      cityId: 'city-nha-trang',
      name: 'Lộc Thọ',
      slug: 'loc-tho',
      isActive: true,
    });
    const service = new LocationBootstrapService(prisma);

    await service.onModuleInit();

    const area = prisma.__areas.get('city-nha-trang:loc-tho');
    expect(area.isActive).toBe(true);
  });

  it('chạy bootstrap nhiều lần không làm thay đổi dữ liệu Admin đã chỉnh (isActive=false giữ nguyên qua nhiều lần)', async () => {
    const prisma = createFakePrisma();
    prisma.__cities.set('nha-trang', { id: 'city-nha-trang', name: 'Nha Trang', slug: 'nha-trang', isActive: true });
    prisma.__areas.set('city-nha-trang:loc-tho', {
      id: 'area-city-nha-trang:loc-tho',
      cityId: 'city-nha-trang',
      name: 'Lộc Thọ',
      slug: 'loc-tho',
      isActive: false,
    });
    const service = new LocationBootstrapService(prisma);

    await service.onModuleInit();
    await service.onModuleInit();
    await service.onModuleInit();

    const area = prisma.__areas.get('city-nha-trang:loc-tho');
    expect(area.isActive).toBe(false);
    // Không tạo thêm bản ghi trùng lặp qua nhiều lần chạy.
    expect(prisma.__areas.size).toBe(17);
  });

  it('không chạy khi NODE_ENV=test', async () => {
    process.env.NODE_ENV = 'test';
    const prisma = createFakePrisma();
    const service = new LocationBootstrapService(prisma);

    await service.onModuleInit();

    expect(prisma.area.upsert).not.toHaveBeenCalled();
    expect(prisma.city.upsert).not.toHaveBeenCalled();
  });
});
