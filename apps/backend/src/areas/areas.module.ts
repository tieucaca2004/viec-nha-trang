import { Controller, Get, Injectable, Module, Query } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class AreasService {
  constructor(private readonly prisma: PrismaService) {}

  async listCities() {
    return this.prisma.city.findMany({ where: { isActive: true } });
  }

  async listAreas(cityId?: string) {
    return this.prisma.area.findMany({
      where: { isActive: true, ...(cityId ? { cityId } : {}) },
      orderBy: { name: 'asc' },
    });
  }
}

@Controller()
export class AreasController {
  constructor(private readonly areasService: AreasService) {}

  @Get('cities')
  listCities() {
    return this.areasService.listCities();
  }

  @Get('areas')
  listAreas(@Query('cityId') cityId?: string) {
    return this.areasService.listAreas(cityId);
  }
}

@Module({
  controllers: [AreasController],
  providers: [AreasService],
  exports: [AreasService],
})
export class AreasModule {}
