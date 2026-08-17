import { Body, Controller, Get, Param, Patch, Post, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { OptionalJwtAuthGuard } from '../common/guards/optional-jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { JobsService } from './jobs.service';
import { CreateJobDto, UpdateJobDto } from './dto/create-job.dto';
import { QueryJobsDto } from './dto/query-jobs.dto';

@ApiTags('Jobs')
@Controller('jobs')
export class JobsController {
  constructor(private readonly jobsService: JobsService) {}

  @Get()
  findMany(@Query() query: QueryJobsDto) {
    return this.jobsService.findMany(query);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('EMPLOYER')
  @Get('mine')
  listMine(@CurrentUser() user: AuthenticatedUser) {
    return this.jobsService.listByEmployer(user.userId);
  }

  // Public endpoint nhưng vẫn nhận diện người gọi NẾU có đăng nhập (chủ tin/admin cần xem job
  // không ACTIVE) - OptionalJwtAuthGuard không throw khi thiếu/token không hợp lệ (đặc tả mục 4
  // của yêu cầu sửa Critical: job không ACTIVE không được public, chỉ owner/admin xem được).
  @ApiBearerAuth()
  @UseGuards(OptionalJwtAuthGuard)
  @Get(':id')
  findOne(@CurrentUser() user: AuthenticatedUser | undefined, @Param('id') id: string) {
    return this.jobsService.findOne(id, user?.userId, user?.roles);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('EMPLOYER')
  @Post()
  create(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateJobDto) {
    return this.jobsService.create(user.userId, dto);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('EMPLOYER')
  @Patch(':id')
  update(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string, @Body() dto: UpdateJobDto) {
    return this.jobsService.update(user.userId, id, dto);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('EMPLOYER')
  @Post(':id/close')
  close(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string) {
    return this.jobsService.close(user.userId, id);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('EMPLOYER')
  @Post(':id/renew')
  renew(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string) {
    return this.jobsService.renew(user.userId, id);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard, RolesGuard)
  @Roles('EMPLOYER')
  @Post(':id/boost')
  boost(@CurrentUser() user: AuthenticatedUser, @Param('id') id: string) {
    return this.jobsService.boost(user.userId, id);
  }
}
