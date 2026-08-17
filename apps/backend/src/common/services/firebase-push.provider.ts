import { Injectable, Logger, OnModuleInit } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { App, cert, getApps, initializeApp } from 'firebase-admin/app';
import { getMessaging } from 'firebase-admin/messaging';
import { PushMessage, PushProvider } from '../interfaces/push-provider.interface';

// Gửi push thật qua Firebase Cloud Messaging. Project Firebase PHẢI là project riêng
// "viec-nha-trang" (đặc tả §1/§4) - service account đọc từ env, không hard-code, không commit.
@Injectable()
export class FirebasePushProvider implements PushProvider, OnModuleInit {
  private readonly logger = new Logger(FirebasePushProvider.name);
  private app?: App;

  constructor(private readonly config: ConfigService) {}

  onModuleInit() {
    // Provider này luôn được Nest khởi tạo (là 1 provider trong module) dù NotificationsModule
    // có thật sự chọn dùng nó qua PUSH_PROVIDER factory hay không - vì vậy KHÔNG throw ở đây
    // khi thiếu cấu hình, chỉ log và để nguyên `this.app` undefined; `send()` mới throw nếu bị
    // gọi nhầm lúc chưa init (không xảy ra trong thực tế vì factory chỉ chọn provider này khi
    // đã có FCM_PROJECT_ID).
    const projectId = this.config.get<string>('FCM_PROJECT_ID');
    const serviceAccountJson = this.config.get<string>('FCM_SERVICE_ACCOUNT_JSON');
    const serviceAccountFile = this.config.get<string>('FCM_SERVICE_ACCOUNT_FILE');

    if (!projectId || (!serviceAccountJson && !serviceAccountFile)) {
      this.logger.warn('FCM_PROJECT_ID chưa cấu hình - FirebasePushProvider sẽ không được dùng (xem NotificationsModule).');
      return;
    }

    const credentialJson = serviceAccountJson ? JSON.parse(serviceAccountJson) : require(serviceAccountFile!);

    this.app =
      getApps().find((a) => a.name === 'viec-nha-trang') ??
      initializeApp({ credential: cert(credentialJson), projectId }, 'viec-nha-trang');

    this.logger.log(`Firebase Cloud Messaging sẵn sàng cho project "${projectId}".`);
  }

  async send(message: PushMessage): Promise<void> {
    if (!this.app) throw new Error('FirebasePushProvider chưa được khởi tạo.');
    await getMessaging(this.app).send({
      token: message.token,
      notification: { title: message.title, body: message.body },
      data: message.data,
    });
  }
}
