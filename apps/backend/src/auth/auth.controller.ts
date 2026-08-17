import { Controller, Body, Inject, NotFoundException, Param, Post, Get } from '@nestjs/common';
import { ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import { RefreshTokenDto, RequestOtpDto, VerifyOtpDto } from './dto/otp.dto';
import { SmsProvider } from '../common/interfaces/sms-provider.interface';
import { ConsoleSmsProvider } from '../common/services/console-sms.provider';
import { SMS_PROVIDER } from '../common/services/tokens';

// Giới hạn có thể chỉnh qua env (mặc định giữ nguyên mức chống spam OTP của production -
// mục 35). E2E test dùng .env.test để nới giới hạn này, vì test chạy nhiều lượt OTP liên
// tiếp từ cùng 1 IP trong thời gian ngắn, khác với hành vi người dùng thật.
const OTP_REQUEST_THROTTLE_LIMIT = Number(process.env.OTP_REQUEST_THROTTLE_LIMIT ?? 3);
const OTP_VERIFY_THROTTLE_LIMIT = Number(process.env.OTP_VERIFY_THROTTLE_LIMIT ?? 5);

@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    @Inject(SMS_PROVIDER) private readonly smsProvider: SmsProvider,
  ) {}

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

  // CHỈ dùng cho load test tự động (docs/LOAD_TESTING.md) - trả 404 (giả vờ không tồn tại)
  // khi NODE_ENV=production hoặc khi SMS provider không phải ConsoleSmsProvider (nghĩa là đã
  // cấu hình gửi SMS thật). Không có cách nào đọc được OTP thật của người dùng qua route này.
  @Get('otp/debug/:phone')
  debugLastOtp(@Param('phone') phone: string) {
    if (process.env.NODE_ENV === 'production' || !(this.smsProvider instanceof ConsoleSmsProvider)) {
      throw new NotFoundException();
    }
    const code = this.smsProvider.getLastCode(phone);
    if (!code) throw new NotFoundException('Chưa có OTP nào được gửi cho số này.');
    return { code };
  }
}
