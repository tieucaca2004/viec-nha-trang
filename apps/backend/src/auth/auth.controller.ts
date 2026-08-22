import { Controller, Body, Inject, NotFoundException, Param, Post, Get, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { Throttle } from '@nestjs/throttler';
import { AuthService } from './auth.service';
import { RefreshTokenDto, RequestOtpDto, VerifyOtpDto } from './dto/otp.dto';
import { RequestEmailVerificationDto, VerifyEmailDto } from './dto/email-verification.dto';
import { RequestPhoneLinkDto, VerifyPhoneLinkDto } from './dto/phone-link.dto';
import { SmsProvider } from '../common/interfaces/sms-provider.interface';
import { EmailProvider } from '../common/interfaces/email-provider.interface';
import { ConsoleSmsProvider } from '../common/services/console-sms.provider';
import { ConsoleEmailProvider } from '../common/services/console-email.provider';
import { SMS_PROVIDER, EMAIL_PROVIDER } from '../common/services/tokens';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';

// Giới hạn có thể chỉnh qua env (mặc định giữ nguyên mức chống spam OTP của production -
// mục 35). E2E test dùng .env.test để nới giới hạn này, vì test chạy nhiều lượt OTP liên
// tiếp từ cùng 1 IP trong thời gian ngắn, khác với hành vi người dùng thật.
const OTP_REQUEST_THROTTLE_LIMIT = Number(process.env.OTP_REQUEST_THROTTLE_LIMIT ?? 3);
const OTP_VERIFY_THROTTLE_LIMIT = Number(process.env.OTP_VERIFY_THROTTLE_LIMIT ?? 5);
const EMAIL_REQUEST_THROTTLE_LIMIT = Number(process.env.EMAIL_VERIFICATION_REQUEST_THROTTLE_LIMIT ?? 3);
const EMAIL_VERIFY_THROTTLE_LIMIT = Number(process.env.EMAIL_VERIFICATION_VERIFY_THROTTLE_LIMIT ?? 5);
// Bug thật trên Beta (xem auth.service.ts): đăng ký và đăng nhập bằng email OTP trước đây dùng
// CHUNG route /auth/register/email/request nên CHUNG luôn hạn mức 3 request/60s/IP - vài lần
// bấm "Gửi lại mã"/thử đăng ký là tiêu hết hạn mức của người khác đang đăng nhập trên cùng
// mạng NAT/proxy. Tách route + hạn mức RIÊNG cho đăng nhập (/auth/login/email/request|verify)
// để 2 luồng không còn ăn chung bucket - vẫn cùng logic nghiệp vụ bên dưới (AuthService đã tự xử
// lý "email có tài khoản -> đăng nhập, chưa có -> tạo mới" từ trước, không đổi hành vi đó).
const EMAIL_LOGIN_REQUEST_THROTTLE_LIMIT = Number(process.env.EMAIL_LOGIN_REQUEST_THROTTLE_LIMIT ?? 3);
const EMAIL_LOGIN_VERIFY_THROTTLE_LIMIT = Number(process.env.EMAIL_LOGIN_VERIFY_THROTTLE_LIMIT ?? 5);

@ApiTags('Auth')
@Controller('auth')
export class AuthController {
  constructor(
    private readonly authService: AuthService,
    @Inject(SMS_PROVIDER) private readonly smsProvider: SmsProvider,
    @Inject(EMAIL_PROVIDER) private readonly emailProvider: EmailProvider,
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

  // Không cần JwtAuthGuard - chính refreshToken trong body là "credential" chứng minh quyền
  // đăng xuất phiên đó (giống /auth/refresh). Idempotent: gọi lại nhiều lần, hoặc gọi với token
  // đã hết hạn/không hợp lệ, đều trả 201 thành công (đặc tả sửa lỗi High #7).
  @Post('logout')
  logout(@Body() dto: RefreshTokenDto) {
    return this.authService.logout(dto.refreshToken);
  }

  @Post('google')
  google(@Body('idToken') idToken: string) {
    return this.authService.loginWithGoogle(idToken);
  }

  @Post('apple')
  apple(@Body('identityToken') identityToken: string) {
    return this.authService.loginWithApple(identityToken);
  }

  // ---------- Đăng ký tài khoản bằng email (đặc tả §1) ----------
  @Throttle({ default: { limit: EMAIL_REQUEST_THROTTLE_LIMIT, ttl: 60_000 } })
  @Post('register/email/request')
  requestEmailVerification(@Body() dto: RequestEmailVerificationDto) {
    return this.authService.requestEmailVerification(dto.email);
  }

  @Throttle({ default: { limit: EMAIL_VERIFY_THROTTLE_LIMIT, ttl: 60_000 } })
  @Post('register/email/verify')
  verifyEmail(@Body() dto: VerifyEmailDto) {
    return this.authService.verifyEmailAndRegister(dto.email, dto.code);
  }

  // ---------- Đăng nhập bằng email OTP - route + hạn mức RIÊNG với đăng ký ở trên ----------
  // Cùng service method (verifyEmailAndRegister đã xử lý cả login lẫn tạo tài khoản mới theo
  // đúng 1 nguyên lý "chứng minh sở hữu email này ngay bây giờ") - chỉ khác throttle bucket, để
  // các lần bấm ở màn Đăng ký không còn làm cạn hạn mức của màn Đăng nhập và ngược lại.
  @Throttle({ default: { limit: EMAIL_LOGIN_REQUEST_THROTTLE_LIMIT, ttl: 60_000 } })
  @Post('login/email/request')
  requestLoginEmailOtp(@Body() dto: RequestEmailVerificationDto) {
    return this.authService.requestEmailVerification(dto.email);
  }

  @Throttle({ default: { limit: EMAIL_LOGIN_VERIFY_THROTTLE_LIMIT, ttl: 60_000 } })
  @Post('login/email/verify')
  verifyLoginEmailOtp(@Body() dto: VerifyEmailDto) {
    return this.authService.verifyEmailAndRegister(dto.email, dto.code);
  }

  // CHỈ dùng cho dev/QA (giống /auth/otp/debug/:phone) - trả 404 khi NODE_ENV=production hoặc
  // khi EMAIL provider không phải ConsoleEmailProvider (đã cấu hình gửi email thật).
  @Get('register/email/debug/:email')
  debugLastEmailCode(@Param('email') email: string) {
    if (process.env.NODE_ENV === 'production' || !(this.emailProvider instanceof ConsoleEmailProvider)) {
      throw new NotFoundException();
    }
    const code = this.emailProvider.getLastCode(email);
    if (!code) throw new NotFoundException('Chưa có mã xác minh nào được gửi cho email này.');
    return { code };
  }

  // ---------- Xác minh số điện thoại cho tài khoản đã đăng nhập (đặc tả §3) ----------
  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: OTP_REQUEST_THROTTLE_LIMIT, ttl: 60_000 } })
  @Post('phone/link/request')
  requestPhoneLink(@CurrentUser() user: AuthenticatedUser, @Body() dto: RequestPhoneLinkDto) {
    return this.authService.requestPhoneLink(user.userId, dto.phone);
  }

  @ApiBearerAuth()
  @UseGuards(JwtAuthGuard)
  @Throttle({ default: { limit: OTP_VERIFY_THROTTLE_LIMIT, ttl: 60_000 } })
  @Post('phone/link/verify')
  verifyPhoneLink(@CurrentUser() user: AuthenticatedUser, @Body() dto: VerifyPhoneLinkDto) {
    return this.authService.verifyPhoneLink(user.userId, dto.phone, dto.code);
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
