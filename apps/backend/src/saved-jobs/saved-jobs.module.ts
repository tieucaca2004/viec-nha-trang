import { Controller, Delete, Get, Injectable, Module, Param, Post, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { PrismaService } from '../prisma/prisma.service';

@Injectable()
export class SavedJobsService {
  constructor(private readonly prisma: PrismaService) {}

  save(userId: string, jobId: string) {
    return this.prisma.savedJob.upsert({
      where: { userId_jobId: { userId, jobId } },
      create: { userId, jobId },
      update: {},
    });
  }

  unsave(userId: string, jobId: string) {
    return this.prisma.savedJob.deleteMany({ where: { userId, jobId } });
  }

  list(userId: string) {
    return this.prisma.savedJob.findMany({
      where: { userId },
      include: { job: { include: { employer: true, area: true, category: true } } },
      orderBy: { createdAt: 'desc' },
    });
  }
}

@ApiTags('Saved Jobs')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('saved-jobs')
export class SavedJobsController {
  constructor(private readonly savedJobsService: SavedJobsService) {}

  @Get()
  list(@CurrentUser() user: AuthenticatedUser) {
    return this.savedJobsService.list(user.userId);
  }

  @Post(':jobId')
  save(@CurrentUser() user: AuthenticatedUser, @Param('jobId') jobId: string) {
    return this.savedJobsService.save(user.userId, jobId);
  }

  @Delete(':jobId')
  unsave(@CurrentUser() user: AuthenticatedUser, @Param('jobId') jobId: string) {
    return this.savedJobsService.unsave(user.userId, jobId);
  }
}

@Module({
  controllers: [SavedJobsController],
  providers: [SavedJobsService],
})
export class SavedJobsModule {}
