// Tách provider gửi SMS OTP để dễ đổi nhà cung cấp (Twilio, eSMS, SpeedSMS, ...) sau này.
export interface SmsProvider {
  sendOtp(phone: string, code: string): Promise<void>;
}
