import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NotificationsController } from './notifications.controller';
import { NotificationsService } from './notifications.service';
import { PUSH_PROVIDER } from '../common/services/tokens';
import { FirebasePushProvider } from '../common/services/firebase-push.provider';
import { NoopPushProvider } from '../common/services/noop-push.provider';

@Module({
  controllers: [NotificationsController],
  providers: [
    NotificationsService,
    FirebasePushProvider,
    NoopPushProvider,
    {
      provide: PUSH_PROVIDER,
      // Chỉ dùng FirebasePushProvider khi đã cấu hình FCM_PROJECT_ID; nếu không, fallback
      // Noop để app chạy được ở dev/CI mà không cần project Firebase thật (mục 9 docs/PLAN.md).
      useFactory: (config: ConfigService, firebase: FirebasePushProvider, noop: NoopPushProvider) =>
        config.get<string>('FCM_PROJECT_ID') ? firebase : noop,
      inject: [ConfigService, FirebasePushProvider, NoopPushProvider],
    },
  ],
  exports: [NotificationsService],
})
export class NotificationsModule {}
