import { Body, Controller, Get, Param, Patch, Post, UseGuards } from '@nestjs/common';
import { ApplicationStatus } from '@prisma/client';
import { IsEnum, IsOptional, IsString } from 'class-validator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { ApplicationsService } from './applications.service';

class UpdateApplicationStatusDto {
  @IsEnum(ApplicationStatus)
  status!: ApplicationStatus;

  @IsOptional()
  @IsString()
  employerNote?: string;
}

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller()
export class ApplicationsController {
  constructor(private readonly applicationsService: ApplicationsService) {}

  @Roles('JOB_SEEKER')
  @Post('jobs/:jobId/apply')
  apply(@CurrentUser() user: AuthenticatedUser, @Param('jobId') jobId: string) {
    return this.applicationsService.apply(user.userId, jobId);
  }

  @Roles('JOB_SEEKER')
  @Get('applications/me')
  listMine(@CurrentUser() user: AuthenticatedUser) {
    return this.applicationsService.listMine(user.userId);
  }

  @Roles('EMPLOYER')
  @Get('employer/jobs/:jobId/applications')
  listForJob(@CurrentUser() user: AuthenticatedUser, @Param('jobId') jobId: string) {
    return this.applicationsService.listForEmployerJob(user.userId, jobId);
  }

  @Roles('EMPLOYER')
  @Patch('applications/:id/status')
  updateStatus(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Body() dto: UpdateApplicationStatusDto,
  ) {
    return this.applicationsService.updateStatus(user.userId, id, dto.status, dto.employerNote);
  }
}
