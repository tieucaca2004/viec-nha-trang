import { Body, Controller, Post } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import { RefreshTokenDto, RequestOtpDto, VerifyOtpDto } from './dto/otp.dto';

// Giới hạn có thể chỉnh qua env (mặc định giữ nguyên mức chống spam OTP của production -
// mục 35). E2E test dùng .env.test để nới giới hạn này, vì test chạy nhiều lượt OTP liên
// tiếp từ cùng 1 IP trong thời gian ngắn, khác với hành vi người dùng thật.
const OTP_REQUEST_THROTTLE_LIMIT = Number(process.env.OTP_REQUEST_THROTTLE_LIMIT ?? 3);
const OTP_VERIFY_THROTTLE_LIMIT = Number(process.env.OTP_VERIFY_THROTTLE_LIMIT ?? 5);

@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(private readonly authService: AuthService) {}

  @Throttle({ default: { limit: OTP_REQUEST_THROTTLE_LIMIT, ttl: 60_000 } })
  @Post('otp/request')
  requestOtp(@Body() dto: RequestOtpDto) {
    return this.authService.requestOtp(dto.phone);
  }

  @Throttle({ default: { limit: OTP_VERIFY_THROTTLE_LIMIT, ttl: 60_000 } })
  @Post('otp/verify')
  verifyOtp(@Body() dto: VerifyOtpDto) {
    return this.authService.verifyOtp(dto.phone, dto.code);
  }

  @Post('refresh')
  refresh(@Body() dto: RefreshTokenDto) {
    return this.authService.refresh(dto.refreshToken);
  }

  @Post('google')
  google(@Body('idToken') idToken: string) {
    return this.authService.loginWithGoogle(idToken);
  }

  @Post('apple')
  apple(@Body('identityToken') identityToken: string) {
    return this.authService.loginWithApple(identityToken);
  }
}
