import { Body, Controller, Get, Injectable, Module, Post, Query, UseGuards } from '@nestjs/common';
import { BadRequestException } from '@nestjs/common';
import { IsEnum, IsInt, IsObject, IsOptional, IsString, Max, Min } from 'class-validator';
import { ReviewerType } from '@prisma/client';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { PrismaService } from '../prisma/prisma.service';

class CreateReviewDto {
  @IsEnum(ReviewerType)
  reviewerType!: ReviewerType;

  @IsOptional()
  @IsString()
  employerId?: string;

  @IsOptional()
  @IsString()
  jobSeekerId?: string;

  @IsOptional()
  @IsString()
  applicationId?: string;

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
  async create(userId: string, dto: CreateReviewDto) {
    if (dto.applicationId) {
      const application = await this.prisma.application.findUnique({
        where: { id: dto.applicationId },
        include: { job: { include: { employer: true } }, jobSeeker: true },
      });
      if (!application || application.status !== 'HIRED') {
        throw new BadRequestException('Chỉ có thể đánh giá sau khi xác nhận đã làm việc.');
      }
    }

    const review = await this.prisma.review.create({
      data: {
        reviewerUserId: userId,
        reviewerType: dto.reviewerType,
        employerId: dto.employerId,
        jobSeekerId: dto.jobSeekerId,
        applicationId: dto.applicationId,
        rating: dto.rating,
        criteriaScores: dto.criteriaScores,
        comment: dto.comment,
      },
    });

    if (dto.employerId) {
      await this.recomputeEmployerRating(dto.employerId);
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
