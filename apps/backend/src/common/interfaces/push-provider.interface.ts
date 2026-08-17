// Interface trung lập cho push notification - hiện thực bằng Firebase Cloud Messaging,
// nhưng call site (NotificationsService) không phụ thuộc trực tiếp vào firebase-admin,
// nên có thể đổi provider sau này mà không đổi code gọi nó.
export interface PushMessage {
  token: string;
  title: string;
  body: string;
  data?: Record<string, string>;
}

export interface PushProvider {
  send(message: PushMessage): Promise<void>;
}
