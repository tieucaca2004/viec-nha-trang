import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
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
    // Ngày sinh (đặc tả §2): dto.dateOfBirth là string ISO date, cần validate "không tương lai"
    // tại đây (thời điểm động, không thể khai báo cố định bằng class-validator decorator) rồi
    // chuyển sang Date thật cho Prisma (cột date_of_birth kiểu DATE).
    const { dateOfBirth, ...rest } = dto;
    let dateOfBirthValue: Date | undefined;
    if (dateOfBirth !== undefined) {
      const parsed = new Date(dateOfBirth);
      if (parsed.getTime() > Date.now()) {
        throw new BadRequestException('Ngày sinh không được ở tương lai.');
      }
      dateOfBirthValue = parsed;
    }

    const data = { ...rest, ...(dateOfBirthValue !== undefined ? { dateOfBirth: dateOfBirthValue } : {}) };

    return this.prisma.jobSeekerProfile.upsert({
      where: { userId },
      create: { userId, ...data },
      update: { ...data },
    });
  }
}
