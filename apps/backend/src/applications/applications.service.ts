import { BadRequestException, ForbiddenException, Injectable, NotFoundException } from '@nestjs/common';
import { ApplicationStatus } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { MatchScoreService } from '../common/services/match-score.service';
import { NotificationsService } from '../notifications/notifications.service';

const NEXT_ALLOWED_STATUS: Record<ApplicationStatus, ApplicationStatus[]> = {
  NEW: ['VIEWED', 'CONTACTED', 'NOT_SUITABLE'],
  VIEWED: ['CONTACTED', 'NOT_SUITABLE'],
  CONTACTED: ['INTERVIEW', 'NOT_SUITABLE'],
  INTERVIEW: ['HIRED', 'NOT_SUITABLE', 'NO_SHOW'],
  HIRED: [],
  NOT_SUITABLE: [],
  NO_SHOW: [],
};

@Injectable()
export class ApplicationsService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly matchScoreService: MatchScoreService,
    private readonly notificationsService: NotificationsService,
  ) {}

  // Ứng tuyển 1 chạm (mục 11): không cần CV, chỉ cần hồ sơ cơ bản đã có sẵn.
  async apply(userId: string, jobId: string) {
    const seeker = await this.prisma.jobSeekerProfile.findUnique({ where: { userId } });
    if (!seeker) throw new BadRequestException('Vui lòng tạo hồ sơ tìm việc trước khi ứng tuyển.');

    const job = await this.prisma.job.findUnique({ where: { id: jobId } });
    if (!job || job.deletedAt || job.status !== 'ACTIVE') {
      throw new NotFoundException('Tin tuyển dụng không còn khả dụng.');
    }

    const existing = await this.prisma.application.findUnique({
      where: { jobId_jobSeekerId: { jobId, jobSeekerId: seeker.id } },
    });
    if (existing) return existing;

    const matchScore = this.matchScoreService.computeScore(job, seeker);

    const application = await this.prisma.$transaction(async (tx) => {
      const created = await tx.application.create({
        data: { jobId, jobSeekerId: seeker.id, matchScore, status: 'NEW' },
      });
      await tx.job.update({ where: { id: jobId }, data: { applicationCount: { increment: 1 } } });
      return created;
    });

    const employer = await this.prisma.employerProfile.findUnique({ where: { id: job.employerId } });
    if (employer) {
      await this.notificationsService.notify(employer.userId, 'NEW_APPLICATION', 'Bạn có ứng viên mới', `Có người vừa ứng tuyển vào "${job.title}".`, { jobId, applicationId: application.id });
    }

    return application;
  }

  async listMine(userId: string) {
    const seeker = await this.prisma.jobSeekerProfile.findUnique({ where: { userId } });
    if (!seeker) return [];
    return this.prisma.application.findMany({
      where: { jobSeekerId: seeker.id },
      include: { job: { include: { employer: true, area: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }

  async listForEmployerJob(userId: string, jobId: string) {
    const job = await this.prisma.job.findUnique({ where: { id: jobId }, include: { employer: true } });
    if (!job || job.employer.userId !== userId) throw new ForbiddenException('Bạn không có quyền xem ứng viên tin này.');
    return this.prisma.application.findMany({
      where: { jobId },
      include: { jobSeeker: true },
      orderBy: { createdAt: 'desc' },
    });
  }

  async updateStatus(userId: string, applicationId: string, status: ApplicationStatus, employerNote?: string) {
    const application = await this.prisma.application.findUnique({
      where: { id: applicationId },
      include: { job: { include: { employer: true } }, jobSeeker: true },
    });
    if (!application || application.job.employer.userId !== userId) {
      throw new ForbiddenException('Bạn không có quyền với ứng viên này.');
    }

    const allowed = NEXT_ALLOWED_STATUS[application.status];
    if (application.status !== status && !allowed.includes(status)) {
      throw new BadRequestException(`Không thể chuyển trạng thái từ ${application.status} sang ${status}.`);
    }

    const updated = await this.prisma.application.update({
      where: { id: applicationId },
      data: { status, employerNote },
    });

    if (status === 'CONTACTED') {
      await this.prisma.job.update({ where: { id: application.jobId }, data: { contactedCount: { increment: 1 } } });
    } else if (status === 'INTERVIEW') {
      await this.prisma.job.update({ where: { id: application.jobId }, data: { interviewCount: { increment: 1 } } });
    } else if (status === 'HIRED') {
      await this.prisma.job.update({ where: { id: application.jobId }, data: { hiredCount: { increment: 1 } } });
    }

    if (status === 'VIEWED') {
      await this.notificationsService.notify(
        application.jobSeeker.userId,
        'APPLICATION_VIEWED',
        'Nhà tuyển dụng đã xem hồ sơ của bạn',
        `Hồ sơ của bạn cho tin "${application.jobId}" đã được xem.`,
        { applicationId },
      );
    } else {
      await this.notificationsService.notify(
        application.jobSeeker.userId,
        'APPLICATION_STATUS_CHANGED',
        'Trạng thái ứng tuyển đã thay đổi',
        `Đơn ứng tuyển của bạn chuyển sang trạng thái: ${status}.`,
        { applicationId, status },
      );
    }

    return updated;
  }
}
