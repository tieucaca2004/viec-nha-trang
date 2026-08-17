import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { JobStatus, ReportStatus, VerificationLevel } from '@prisma/client';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { AdminService } from './admin.service';

@ApiTags('Admin')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('ADMIN')
@Controller('admin')
export class AdminController {
  constructor(private readonly adminService: AdminService) {}

  @Get('dashboard')
  dashboard() {
    return this.adminService.dashboard();
  }

  @Get('users')
  listUsers(@Query('skip') skip?: string, @Query('take') take?: string) {
    return this.adminService.listUsers({ skip: Number(skip) || 0, take: Number(take) || 20 });
  }

  @Post('users/:id/ban')
  banUser(@CurrentUser() admin: AuthenticatedUser, @Param('id') id: string, @Body('reason') reason: string) {
    return this.adminService.banUser(admin.userId, id, reason);
  }

  @Post('users/:id/unban')
  unbanUser(@CurrentUser() admin: AuthenticatedUser, @Param('id') id: string) {
    return this.adminService.unbanUser(admin.userId, id);
  }

  @Get('employers')
  listEmployers(@Query('skip') skip?: string, @Query('take') take?: string) {
    return this.adminService.listEmployers({ skip: Number(skip) || 0, take: Number(take) || 20 });
  }

  @Post('employers/:id/verify')
  verifyEmployer(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('id') id: string,
    @Body('level') level: VerificationLevel,
  ) {
    return this.adminService.verifyEmployer(admin.userId, id, level);
  }

  @Get('jobs')
  listJobs(@Query('skip') skip?: string, @Query('take') take?: string, @Query('status') status?: JobStatus) {
    return this.adminService.listJobs({ skip: Number(skip) || 0, take: Number(take) || 20, status });
  }

  @Patch('jobs/:id/status')
  setJobStatus(@CurrentUser() admin: AuthenticatedUser, @Param('id') id: string, @Body('status') status: JobStatus) {
    return this.adminService.setJobStatus(admin.userId, id, status);
  }

  @Post('jobs/:id/remove')
  removeJob(@CurrentUser() admin: AuthenticatedUser, @Param('id') id: string) {
    return this.adminService.removeJob(admin.userId, id);
  }

  @Get('applications')
  listApplications(@Query('skip') skip?: string, @Query('take') take?: string) {
    return this.adminService.listApplications({ skip: Number(skip) || 0, take: Number(take) || 20 });
  }

  @Get('reports')
  listReports(@Query('skip') skip?: string, @Query('take') take?: string, @Query('status') status?: ReportStatus) {
    return this.adminService.listReports({ skip: Number(skip) || 0, take: Number(take) || 20, status });
  }

  @Patch('reports/:id/resolve')
  resolveReport(
    @CurrentUser() admin: AuthenticatedUser,
    @Param('id') id: string,
    @Body('status') status: ReportStatus,
    @Body('resolvedNote') resolvedNote?: string,
  ) {
    return this.adminService.resolveReport(admin.userId, id, status, resolvedNote);
  }

  @Get('categories')
  listCategories() {
    return this.adminService.listCategories();
  }

  @Post('categories')
  createCategory(@CurrentUser() admin: AuthenticatedUser, @Body() data: { name: string; slug: string; icon?: string; sortOrder?: number }) {
    return this.adminService.createCategory(admin.userId, data);
  }

  @Patch('categories/:id')
  updateCategory(@CurrentUser() admin: AuthenticatedUser, @Param('id') id: string, @Body() data: Record<string, unknown>) {
    return this.adminService.updateCategory(admin.userId, id, data);
  }

  @Get('areas')
  listAreas(@Query('cityId') cityId?: string) {
    return this.adminService.listAreas(cityId);
  }

  @Post('areas')
  createArea(@CurrentUser() admin: AuthenticatedUser, @Body() data: { cityId: string; name: string; slug: string }) {
    return this.adminService.createArea(admin.userId, data);
  }

  @Patch('areas/:id')
  updateArea(@CurrentUser() admin: AuthenticatedUser, @Param('id') id: string, @Body() data: Record<string, unknown>) {
    return this.adminService.updateArea(admin.userId, id, data);
  }
}
