// Tách provider gửi email xác minh để dễ đổi nhà cung cấp (SMTP tự cấu hình, SES, SendGrid,
// ...) sau này - cùng pattern với SmsProvider (xem sms-provider.interface.ts).
export interface EmailProvider {
  sendVerificationEmail(email: string, code: string): Promise<void>;
}
