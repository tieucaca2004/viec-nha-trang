import { Injectable, NotFoundException } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { UpsertJobSeekerProfileDto } from './dto/upsert-job-seeker-profile.dto';

@Injectable()
export class JobSeekersService {
  constructor(private readonly prisma: PrismaService) {}

  async getMyProfile(userId: string) {
    const profile = await this.prisma.jobSeekerProfile.findUnique({ where: { userId } });
    if (!profile) throw new NotFoundException('Chưa có hồ sơ người tìm việc.');
    return profile;
  }

  async upsertMyProfile(userId: string, dto: UpsertJobSeekerProfileDto) {
    return this.prisma.jobSeekerProfile.upsert({
      where: { userId },
      create: { userId, ...dto },
      update: { ...dto },
    });
  }
}
