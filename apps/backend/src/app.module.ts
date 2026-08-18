import { Module } from '@nestjs/common';
import { APP_GUARD } from '@nestjs/core';
import { ConfigModule } from '@nestjs/config';
import { ThrottlerGuard, ThrottlerModule } from '@nestjs/throttler';
import { HealthController } from './health/health.controller';
import { PrismaModule } from './prisma/prisma.module';
import { AuthModule } from './auth/auth.module';
import { UsersModule } from './users/users.module';
import { JobSeekersModule } from './job-seekers/job-seekers.module';
import { EmployersModule } from './employers/employers.module';
import { CategoriesModule } from './categories/categories.module';
import { AreasModule } from './areas/areas.module';
import { JobsModule } from './jobs/jobs.module';
import { ApplicationsModule } from './applications/applications.module';
import { SavedJobsModule } from './saved-jobs/saved-jobs.module';
import { ReviewsModule } from './reviews/reviews.module';
import { ReportsModule } from './reports/reports.module';
import { NotificationsModule } from './notifications/notifications.module';
import { AdminModule } from './admin/admin.module';

@Module({
  imports: [
    ConfigModule.forRoot({ isGlobal: true, envFilePath: [`.env.${process.env.NODE_ENV ?? 'development'}`, '.env'] }),
    ThrottlerModule.forRoot({
      throttlers: [
        { ttl: Number(process.env.THROTTLE_TTL ?? 60) * 1000, limit: Number(process.env.THROTTLE_LIMIT ?? 60) },
      ],
    }),
    PrismaModule,
    AuthModule,
    UsersModule,
    JobSeekersModule,
    EmployersModule,
    CategoriesModule,
    AreasModule,
    JobsModule,
    ApplicationsModule,
    SavedJobsModule,
    ReviewsModule,
    ReportsModule,
    NotificationsModule,
    AdminModule,
  ],
  controllers: [HealthController],
  providers: [{ provide: APP_GUARD, useClass: ThrottlerGuard }],
})
export class AppModule {}
