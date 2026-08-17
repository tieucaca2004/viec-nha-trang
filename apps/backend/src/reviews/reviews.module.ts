import { Body, Controller, Get, Injectable, Module, Post, Query, UseGuards } from '@nestjs/common';
import { BadRequestException, ForbiddenException, NotFoundException } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsEnum, IsInt, IsObject, IsOptional, IsString, Max, Min } from 'class-validator';
import { ReviewerType } from '@prisma/client';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { PrismaService } from '../prisma/prisma.service';

class CreateReviewDto {
  @IsEnum(ReviewerType)
  reviewerType!: ReviewerType;

  // Bắt buộc (sửa lỗi Critical #5 FULL AUDIT): trước đây optional nên bỏ field này là bypass
  // hoàn toàn kiểm tra HIRED. employerId/jobSeekerId KHÔNG còn nhận từ client - service tự suy
  // ra từ chính applicationId để không ai giả mạo đang đánh giá một employer/seeker không liên
  // quan tới đơn ứng tuyển thật của mình.
  @IsString()
  applicationId!: string;

  @IsInt()
  @Min(1)
  @Max(5)
  rating!: number;

  @IsOptional()
  @IsObject()
  criteriaScores?: Record<string, number>;

  @IsOptional()
  @IsString()
  comment?: string;
}

@Injectable()
export class ReviewsService {
  constructor(private readonly prisma: PrismaService) {}

  // Chỉ cho đánh giá khi có application ở trạng thái HIRED - xác nhận "đã thực sự làm việc" (mục 23).
  // Application phải thuộc đúng người gọi (không phải chỉ tồn tại) và đúng vai trò khai báo.
  async create(userId: string, dto: CreateReviewDto) {
    const application = await this.prisma.application.findUnique({
      where: { id: dto.applicationId },
      include: { job: { include: { employer: true } }, jobSeeker: true },
    });
    if (!application) {
      throw new NotFoundException('Không tìm thấy đơn ứng tuyển.');
    }
    if (application.status !== 'HIRED') {
      throw new BadRequestException('Chỉ có thể đánh giá sau khi đơn ứng tuyển đã ở trạng thái đã được tuyển (HIRED).');
    }

    const isSeekerOfApplication = application.jobSeeker.userId === userId;
    const isEmployerOfApplication = application.job.employer.userId === userId;

    if (dto.reviewerType === 'JOB_SEEKER' && !isSeekerOfApplication) {
      throw new ForbiddenException('Đơn ứng tuyển này không thuộc về bạn.');
    }
    if (dto.reviewerType === 'EMPLOYER' && !isEmployerOfApplication) {
      throw new ForbiddenException('Đơn ứng tuyển này không thuộc về nhà tuyển dụng của bạn.');
    }

    // Suy ra employerId/jobSeekerId từ application thật, không tin dto - tránh 1 reviewer hợp lệ
    // (đúng application, đúng HIRED) nhưng cố tình khai employerId/jobSeekerId khác để chấm điểm
    // sai đối tượng không liên quan tới đơn ứng tuyển này.
    const employerId = application.job.employerId;
    const jobSeekerId = application.jobSeekerId;

    const review = await this.prisma.review.create({
      data: {
        reviewerUserId: userId,
        reviewerType: dto.reviewerType,
        employerId,
        jobSeekerId,
        applicationId: dto.applicationId,
        rating: dto.rating,
        criteriaScores: dto.criteriaScores,
        comment: dto.comment,
      },
    });

    // ratingAvg/ratingCount chỉ tồn tại trên EmployerProfile (schema.prisma) - chỉ có ý nghĩa
    // khi job seeker đang đánh giá employer, không phải chiều ngược lại.
    if (dto.reviewerType === 'JOB_SEEKER') {
      await this.recomputeEmployerRating(employerId);
    }

    return review;
  }

  async listForTarget(targetType: 'employer' | 'jobSeeker', targetId: string) {
    return this.prisma.review.findMany({
      where: targetType === 'employer' ? { employerId: targetId } : { jobSeekerId: targetId },
      orderBy: { createdAt: 'desc' },
    });
  }

  private async recomputeEmployerRating(employerId: string) {
    const agg = await this.prisma.review.aggregate({
      where: { employerId },
      _avg: { rating: true },
      _count: { rating: true },
    });
    await this.prisma.employerProfile.update({
      where: { id: employerId },
      data: { ratingAvg: agg._avg.rating ?? 0, ratingCount: agg._count.rating },
    });
  }
}

@ApiTags('Reviews')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('reviews')
export class ReviewsController {
  constructor(private readonly reviewsService: ReviewsService) {}

  @Post()
  create(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateReviewDto) {
    return this.reviewsService.create(user.userId, dto);
  }

  @Get()
  list(@Query('targetType') targetType: 'employer' | 'jobSeeker', @Query('targetId') targetId: string) {
    return this.reviewsService.listForTarget(targetType, targetId);
  }
}

@Module({
  controllers: [ReviewsController],
  providers: [ReviewsService],
})
export class ReviewsModule {}
