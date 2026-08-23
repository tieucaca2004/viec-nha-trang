import { Controller, Get, Injectable, Module, Query } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { PrismaService } from '../prisma/prisma.service';
import { normalizeVietnamese } from './normalize-vi.util';

@Injectable()
export class AreasService {
  constructor(private readonly prisma: PrismaService) {}

  async listCities() {
    return this.prisma.city.findMany({ where: { isActive: true } });
  }

  // `search` mở rộng backward-compatible (Phase F - đặc tả §4/§8): khi có, match cả tên hiện
  // hành (contains, không phân biệt hoa/thường) LẪN địa danh cũ qua AreaAlias.normalizedName
  // (không phân biệt dấu, vd "vinh hai" khớp "Vĩnh Hải"). Không search -> hành vi y hệt cũ.
  // Response luôn thêm field `aliases` (mảng tên cũ, rỗng nếu chưa có) - mobile Area.fromJson()
  // hiện tại chỉ đọc id/name nên field mới không phá tương thích ngược.
  async listAreas(cityId?: string, search?: string) {
    const normalizedSearch = search?.trim() ? normalizeVietnamese(search) : undefined;

    const areas = await this.prisma.area.findMany({
      where: {
        isActive: true,
        ...(cityId ? { cityId } : {}),
        ...(normalizedSearch
          ? {
              OR: [
                { name: { contains: search, mode: 'insensitive' } },
                { aliases: { some: { normalizedName: { contains: normalizedSearch } } } },
              ],
            }
          : {}),
      },
      include: { aliases: true },
      orderBy: { name: 'asc' },
    });

    return areas.map((area) => ({
      id: area.id,
      cityId: area.cityId,
      name: area.name,
      slug: area.slug,
      isActive: area.isActive,
      aliases: area.aliases.map((alias) => alias.name),
    }));
  }
}

@ApiTags('Areas')
@Controller()
export class AreasController {
  constructor(private readonly areasService: AreasService) {}

  @Get('cities')
  listCities() {
    return this.areasService.listCities();
  }

  @Get('areas')
  listAreas(@Query('cityId') cityId?: string, @Query('search') search?: string) {
    return this.areasService.listAreas(cityId, search);
  }
}

@Module({
  controllers: [AreasController],
  providers: [AreasService],
  exports: [AreasService],
})
export class AreasModule {}
