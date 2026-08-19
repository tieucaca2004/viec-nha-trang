import { IsPhoneNumber, IsString, Length } from 'class-validator';

// Xác minh số điện thoại cho tài khoản ĐÃ đăng nhập (khác /auth/otp/* dùng để đăng nhập/đăng ký
// bằng SMS OTP) - dùng khi cần xác minh phone trước khi ứng tuyển/đăng tuyển (đặc tả §3).
export class RequestPhoneLinkDto {
  @IsPhoneNumber('VN')
  phone!: string;
}

export class VerifyPhoneLinkDto {
  @IsPhoneNumber('VN')
  phone!: string;

  @IsString()
  @Length(4, 8)
  code!: string;
}
