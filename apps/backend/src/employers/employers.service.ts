import { ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UpsertEmployerProfileDto, CreateEmployerLocationDto } from './dto/employer.dto';

@Injectable()
export class EmployersService {
  constructor(private readonly prisma: PrismaService) {}

  async getMyProfile(userId: string) {
    const profile = await this.prisma.employerProfile.findUnique({
      where: { userId },
      include: { locations: true },
    });
    if (!profile) throw new NotFoundException('Chưa có hồ sơ nhà tuyển dụng.');
    return profile;
  }

  async upsertMyProfile(userId: string, dto: UpsertEmployerProfileDto) {
    return this.prisma.employerProfile.upsert({
      where: { userId },
      create: { userId, ...dto },
      update: { ...dto },
    });
  }

  async addLocation(userId: string, dto: CreateEmployerLocationDto) {
    const employer = await this.prisma.employerProfile.findUnique({ where: { userId } });
    if (!employer) throw new NotFoundException('Chưa có hồ sơ nhà tuyển dụng, hãy tạo hồ sơ trước.');
    return this.prisma.employerLocation.create({ data: { employerId: employer.id, ...dto } });
  }

  async listMyLocations(userId: string) {
    const employer = await this.prisma.employerProfile.findUnique({ where: { userId } });
    if (!employer) return [];
    return this.prisma.employerLocation.findMany({ where: { employerId: employer.id, deletedAt: null } });
  }

  async assertOwnsEmployer(userId: string, employerId: string) {
    const employer = await this.prisma.employerProfile.findUnique({ where: { id: employerId } });
    if (!employer || employer.userId !== userId) {
      throw new ForbiddenException('Bạn không có quyền với nhà tuyển dụng này.');
    }
    return employer;
  }
}
