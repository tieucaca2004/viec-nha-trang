import { Injectable, NotFoundException } from '@nestjs/common';
import { JobStatus, Prisma, ReportStatus, VerificationLevel } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class AdminService {
  constructor(private readonly prisma: PrismaService) {}

  async dashboard() {
    const [totalUsers, totalJobSeekers, totalEmployers, activeJobs, newJobsToday, applications, reportsOpen] =
      await Promise.all([
        this.prisma.user.count({ where: { deletedAt: null } }),
        this.prisma.jobSeekerProfile.count(),
        this.prisma.employerProfile.count(),
        this.prisma.job.count({ where: { status: 'ACTIVE', deletedAt: null } }),
        this.prisma.job.count({ where: { createdAt: { gte: new Date(new Date().setHours(0, 0, 0, 0)) } } }),
        this.prisma.application.count(),
        this.prisma.report.count({ where: { status: 'OPEN' } }),
      ]);

    return { totalUsers, totalJobSeekers, totalEmployers, activeJobs, newJobsToday, applications, reportsOpen };
  }

  // ---- Users ----
  listUsers(params: { skip?: number; take?: number }) {
    return this.prisma.user.findMany({
      where: { deletedAt: null },
      orderBy: { createdAt: 'desc' },
      skip: params.skip ?? 0,
      take: params.take ?? 20,
    });
  }

  async banUser(adminId: string, userId: string, reason: string) {
    const user = await this.prisma.user.update({
      where: { id: userId },
      data: { isBanned: true, bannedReason: reason },
    });
    await this.audit(adminId, 'user.ban', 'User', userId, { reason });
    return user;
  }

  async unbanUser(adminId: string, userId: string) {
    const user = await this.prisma.user.update({ where: { id: userId }, data: { isBanned: false, bannedReason: null } });
    await this.audit(adminId, 'user.unban', 'User', userId);
    return user;
  }

  // ---- Employers ----
  listEmployers(params: { skip?: number; take?: number }) {
    return this.prisma.employerProfile.findMany({
      orderBy: { createdAt: 'desc' },
      skip: params.skip ?? 0,
      take: params.take ?? 20,
      include: { user: true, locations: true },
    });
  }

  async verifyEmployer(adminId: string, employerId: string, level: VerificationLevel) {
    const employer = await this.prisma.employerProfile.findUnique({ where: { id: employerId } });
    if (!employer) throw new NotFoundException('Không tìm thấy nhà tuyển dụng.');
    const updated = await this.prisma.employerProfile.update({
      where: { id: employerId },
      data: { verificationLevel: level },
    });
    await this.audit(adminId, 'employer.verify', 'EmployerProfile', employerId, { level });
    return updated;
  }

  // ---- Jobs ----
  listJobs(params: { skip?: number; take?: number; status?: JobStatus }) {
    return this.prisma.job.findMany({
      where: { deletedAt: null, ...(params.status ? { status: params.status } : {}) },
      orderBy: { createdAt: 'desc' },
      skip: params.skip ?? 0,
      take: params.take ?? 20,
      include: { employer: true, category: true, area: true },
    });
  }

  async setJobStatus(adminId: string, jobId: string, status: JobStatus) {
    const job = await this.prisma.job.update({ where: { id: jobId }, data: { status } });
    await this.audit(adminId, 'job.setStatus', 'Job', jobId, { status });
    return job;
  }

  async removeJob(adminId: string, jobId: string) {
    const job = await this.prisma.job.update({ where: { id: jobId }, data: { deletedAt: new Date(), status: 'REJECTED' } });
    await this.audit(adminId, 'job.remove', 'Job', jobId);
    return job;
  }

  // ---- Applications ----
  listApplications(params: { skip?: number; take?: number }) {
    return this.prisma.application.findMany({
      orderBy: { createdAt: 'desc' },
      skip: params.skip ?? 0,
      take: params.take ?? 20,
      include: { job: true, jobSeeker: true },
    });
  }

  // ---- Reports ----
  listReports(params: { skip?: number; take?: number; status?: ReportStatus }) {
    return this.prisma.report.findMany({
      where: params.status ? { status: params.status } : undefined,
      orderBy: { createdAt: 'desc' },
      skip: params.skip ?? 0,
      take: params.take ?? 20,
    });
  }

  async resolveReport(adminId: string, reportId: string, status: ReportStatus, resolvedNote?: string) {
    const report = await this.prisma.report.update({ where: { id: reportId }, data: { status, resolvedNote } });
    await this.audit(adminId, 'report.resolve', 'Report', reportId, { status, resolvedNote });
    return report;
  }

  // ---- Categories ----
  listCategories() {
    return this.prisma.jobCategory.findMany({ orderBy: { sortOrder: 'asc' } });
  }

  createCategory(adminId: string, data: { name: string; slug: string; icon?: string; sortOrder?: number }) {
    return this.prisma.jobCategory.create({ data }).then((c) => {
      this.audit(adminId, 'category.create', 'JobCategory', c.id);
      return c;
    });
  }

  updateCategory(adminId: string, id: string, data: Partial<{ name: string; icon: string; sortOrder: number; isActive: boolean }>) {
    return this.prisma.jobCategory.update({ where: { id }, data }).then((c) => {
      this.audit(adminId, 'category.update', 'JobCategory', id, data);
      return c;
    });
  }

  // ---- Areas ----
  listAreas(cityId?: string) {
    return this.prisma.area.findMany({ where: cityId ? { cityId } : undefined, orderBy: { name: 'asc' } });
  }

  createArea(adminId: string, data: { cityId: string; name: string; slug: string }) {
    return this.prisma.area.create({ data }).then((a) => {
      this.audit(adminId, 'area.create', 'Area', a.id);
      return a;
    });
  }

  updateArea(adminId: string, id: string, data: Partial<{ name: string; isActive: boolean }>) {
    return this.prisma.area.update({ where: { id }, data }).then((a) => {
      this.audit(adminId, 'area.update', 'Area', id, data);
      return a;
    });
  }

  private audit(actorId: string, action: string, targetType: string, targetId: string, metadata?: Record<string, unknown>) {
    return this.prisma.auditLog.create({
      data: { actorId, action, targetType, targetId, metadata: metadata as Prisma.InputJsonValue | undefined },
    });
  }
}
