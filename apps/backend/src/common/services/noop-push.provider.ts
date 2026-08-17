import { Injectable, Logger } from '@nestjs/common';
import { PushMessage, PushProvider } from '../interfaces/push-provider.interface';

// Dùng khi chưa cấu hình Firebase (FCM_PROJECT_ID rỗng) - app vẫn chạy bình thường ở dev/CI
// không cần project Firebase thật, chỉ log cảnh báo thay vì gửi push.
@Injectable()
export class NoopPushProvider implements PushProvider {
  private readonly logger = new Logger(NoopPushProvider.name);

  async send(message: PushMessage): Promise<void> {
    this.logger.warn(`[PUSH DISABLED] Chưa cấu hình FCM_PROJECT_ID - bỏ qua push tới token=${message.token.slice(0, 12)}...`);
  }
}
