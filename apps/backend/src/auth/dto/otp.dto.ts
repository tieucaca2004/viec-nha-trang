import { IsPhoneNumber, IsString, Length } from 'class-validator';

export class RequestOtpDto {
  @IsPhoneNumber('VN')
  phone!: string;
}

export class VerifyOtpDto {
  @IsPhoneNumber('VN')
  phone!: string;

  @IsString()
  @Length(4, 8)
  code!: string;
}

export class RefreshTokenDto {
  @IsString()
  refreshToken!: string;
}
