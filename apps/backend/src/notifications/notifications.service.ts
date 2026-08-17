import { Inject, Injectable, Logger } from '@nestjs/common';
import { NotificationType, Prisma } from '@prisma/client';
import { PrismaService } from '../prisma/prisma.service';
import { PushProvider } from '../common/interfaces/push-provider.interface';
import { PUSH_PROVIDER } from '../common/services/tokens';

// V1: ghi notification vào DB để app poll/hiển thị trong tab Thông báo, đồng thời gửi push
// thật qua FCM nếu user đã đăng ký device token (mục 17, 23). Ghi DB không phụ thuộc vào việc
// gửi push có thành công hay không - lỗi push (token hết hạn, thiết bị gỡ app...) không được
// làm hỏng luồng nghiệp vụ chính (vd tạo application vẫn phải thành công dù push thất bại).
@Injectable()
export class NotificationsService {
  private readonly logger = new Logger(NotificationsService.name);

  constructor(
    private readonly prisma: PrismaService,
    @Inject(PUSH_PROVIDER) private readonly pushProvider: PushProvider,
  ) {}

  async notify(userId: string, type: NotificationType, title: string, body: string, data?: Record<string, unknown>) {
    const notification = await this.prisma.notification.create({
      data: { userId, type, title, body, data: data as Prisma.InputJsonValue | undefined },
    });

    const user = await this.prisma.user.findUnique({ where: { id: userId }, select: { pushToken: true } });
    if (user?.pushToken) {
      try {
        await this.pushProvider.send({
          token: user.pushToken,
          title,
          body,
          data: data ? Object.fromEntries(Object.entries(data).map(([k, v]) => [k, String(v)])) : undefined,
        });
      } catch (error) {
        this.logger.warn(`Gửi push thất bại cho user=${userId}: ${(error as Error).message}`);
      }
    }

    return notification;
  }

  async listForUser(userId: string) {
    return this.prisma.notification.findMany({ where: { userId }, orderBy: { createdAt: 'desc' }, take: 50 });
  }

  async markRead(userId: string, notificationId: string) {
    return this.prisma.notification.updateMany({
      where: { id: notificationId, userId },
      data: { readAt: new Date() },
    });
  }
}
