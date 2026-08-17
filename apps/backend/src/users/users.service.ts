import { BadRequestException, Injectable, NotFoundException } from '@nestjs/common';
import { UserRole } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { SAFE_USER_SELECT } from '../common/services/safe-select';

@Injectable()
export class UsersService {
  constructor(private readonly prisma: PrismaService) {}

  async getMe(userId: string) {
    const user = await this.prisma.user.findUnique({
      where: { id: userId },
      select: { ...SAFE_USER_SELECT, jobSeekerProfile: true, employerProfile: true },
    });
    if (!user) throw new NotFoundException('Không tìm thấy người dùng.');
    return user;
  }

  async addRole(userId: string, role: UserRole) {
    if (role !== 'JOB_SEEKER' && role !== 'EMPLOYER') {
      throw new BadRequestException('Vai trò không hợp lệ.');
    }
    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: userId } });
    if (user.roles.includes(role)) {
      return this.prisma.user.findUnique({ where: { id: userId }, select: SAFE_USER_SELECT });
    }
    return this.prisma.user.update({
      where: { id: userId },
      data: { roles: { set: [...user.roles, role] } },
      select: SAFE_USER_SELECT,
    });
  }
}
