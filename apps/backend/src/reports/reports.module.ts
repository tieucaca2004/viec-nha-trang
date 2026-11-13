import { BadRequestException, Body, Controller, Injectable, Module, NotFoundException, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsEnum, IsOptional, IsString } from 'class-validator';
import { ReportReason, ReportTargetType } from '@prisma/client';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { PrismaService } from '../prisma/prisma.service';

class CreateReportDto {
  @IsEnum(ReportTargetType)
  targetType!: ReportTargetType;

  @IsOptional()
  @IsString()
  jobId?: string;

  @IsOptional()
  @IsString()
  reviewId?: string;

  @IsOptional()
  @IsString()
  targetUserId?: string;

  @IsEnum(ReportReason)
  reason!: ReportReason;

  @IsOptional()
  @IsString()
  note?: string;
}

@Injectable()
export class ReportsService {
  constructor(private readonly prisma: PrismaService) {}

  async create(reporterId: string, dto: CreateReportDto) {
    if (dto.targetType === 'JOB') {
      if (!dto.jobId) {
        throw new BadRequestException('Báo cáo tin tuyển dụng cần có jobId.');
      }
      if (dto.reviewId || dto.targetUserId) {
        throw new BadRequestException('Báo cáo tin tuyển dụng chỉ nhận jobId.');
      }
      // Kiểm tra trước thay vì để FK violation của Prisma rơi thành 500.
      const job = await this.prisma.job.findUnique({ where: { id: dto.jobId }, select: { id: true } });
      if (!job) {
        throw new NotFoundException('Không tìm thấy tin tuyển dụng.');
      }
    }
    return this.prisma.report.create({ data: { reporterId, ...dto } });
  }
}

@ApiTags('Reports')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('reports')
export class ReportsController {
  constructor(private readonly reportsService: ReportsService) {}

  @Post()
  create(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateReportDto) {
    return this.reportsService.create(user.userId, dto);
  }
}

@Module({
  controllers: [ReportsController],
  providers: [ReportsService],
  exports: [ReportsService],
})
export class ReportsModule {}
