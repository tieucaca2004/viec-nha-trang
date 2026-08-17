import { Module } from '@nestjs/common';
import { ApplicationsController } from './applications.controller';
import { ApplicationsService } from './applications.service';
import { NotificationsModule } from '../notifications/notifications.module';
import { MatchScoreService } from '../common/services/match-score.service';

@Module({
  imports: [NotificationsModule],
  controllers: [ApplicationsController],
  providers: [ApplicationsService, MatchScoreService],
  exports: [ApplicationsService],
})
export class ApplicationsModule {}
