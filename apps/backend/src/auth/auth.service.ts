import { BadRequestException, Injectable, NotImplementedException, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtService } from '@nestjs/jwt';
import { Inject } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { SmsProvider } from '../common/interfaces/sms-provider.interface';
import { SMS_PROVIDER } from '../common/services/tokens';
import { generateOtpCode, hashValue, verifyHash } from '../common/services/hash.util';

@Injectable()
export class AuthService {
  constructor(
    private readonly prisma: PrismaService,
    private readonly jwt: JwtService,
    private readonly config: ConfigService,
    @Inject(SMS_PROVIDER) private readonly smsProvider: SmsProvider,
  ) {}

  async requestOtp(phone: string): Promise<{ expiresInSeconds: number }> {
    const ttlSeconds = Number(this.config.get('OTP_TTL_SECONDS') ?? 300);
    const code = generateOtpCode();
    const codeHash = hashValue(code);
    const expiresAt = new Date(Date.now() + ttlSeconds * 1000);

    const user = await this.prisma.user.findUnique({ where: { phone } });

    await this.prisma.otpCode.create({
      data: { phone, codeHash, expiresAt, userId: user?.id },
    });

    await this.smsProvider.sendOtp(phone, code);

    return { expiresInSeconds: ttlSeconds };
  }

  async verifyOtp(phone: string, code: string) {
    const maxAttempts = Number(this.config.get('OTP_MAX_ATTEMPTS') ?? 5);

    const otp = await this.prisma.otpCode.findFirst({
      where: { phone, consumedAt: null, expiresAt: { gt: new Date() } },
      orderBy: { createdAt: 'desc' },
    });

    if (!otp || otp.attempts >= maxAttempts) {
      throw new BadRequestException('Mã OTP không hợp lệ hoặc đã hết hạn.');
    }

    const isValid = verifyHash(code, otp.codeHash);
    if (!isValid) {
      await this.prisma.otpCode.update({ where: { id: otp.id }, data: { attempts: { increment: 1 } } });
      throw new BadRequestException('Mã OTP không đúng.');
    }

    await this.prisma.otpCode.update({ where: { id: otp.id }, data: { consumedAt: new Date() } });

    let user = await this.prisma.user.findUnique({ where: { phone } });
    if (!user) {
      user = await this.prisma.user.create({
        data: { phone, isPhoneVerified: true, roles: ['JOB_SEEKER'], lastLoginAt: new Date() },
      });
    } else if (!user.isPhoneVerified) {
      user = await this.prisma.user.update({
        where: { id: user.id },
        data: { isPhoneVerified: true, lastLoginAt: new Date() },
      });
    } else {
      user = await this.prisma.user.update({ where: { id: user.id }, data: { lastLoginAt: new Date() } });
    }

    if (user.isBanned) {
      throw new UnauthorizedException('Tài khoản đã bị khóa.');
    }

    return this.issueTokens(user.id, user.roles);
  }

  async refresh(refreshToken: string) {
    let payload: { sub: string };
    try {
      payload = this.jwt.verify(refreshToken, { secret: this.config.get('JWT_REFRESH_SECRET') });
    } catch {
      throw new UnauthorizedException('Refresh token không hợp lệ.');
    }

    const tokenRows = await this.prisma.refreshToken.findMany({
      where: { userId: payload.sub, revokedAt: null, expiresAt: { gt: new Date() } },
    });
    const matching = tokenRows.find((row) => verifyHash(refreshToken, row.tokenHash));
    if (!matching) {
      throw new UnauthorizedException('Refresh token không hợp lệ hoặc đã bị thu hồi.');
    }

    const user = await this.prisma.user.findUniqueOrThrow({ where: { id: payload.sub } });
    if (user.isBanned) throw new UnauthorizedException('Tài khoản đã bị khóa.');

    await this.prisma.refreshToken.update({ where: { id: matching.id }, data: { revokedAt: new Date() } });

    return this.issueTokens(user.id, user.roles);
  }

  async loginWithGoogle(_idToken: string): Promise<never> {
    // Điểm mở rộng: xác thực idToken qua Google, tìm/tạo user theo email, issueTokens().
    throw new NotImplementedException('Đăng nhập Google sẽ được bật ở bản phát hành sau.');
  }

  async loginWithApple(_identityToken: string): Promise<never> {
    // Điểm mở rộng: xác thực identityToken qua Apple, tìm/tạo user theo email/sub, issueTokens().
    throw new NotImplementedException('Đăng nhập Apple sẽ được bật ở bản phát hành sau.');
  }

  private async issueTokens(userId: string, roles: string[]) {
    const accessToken = this.jwt.sign(
      { sub: userId, roles },
      { secret: this.config.get('JWT_ACCESS_SECRET'), expiresIn: this.config.get('JWT_ACCESS_EXPIRES_IN') },
    );
    const refreshToken = this.jwt.sign(
      { sub: userId },
      { secret: this.config.get('JWT_REFRESH_SECRET'), expiresIn: this.config.get('JWT_REFRESH_EXPIRES_IN') },
    );

    const refreshExpiresInDays = this.parseDaysFromExpiresIn(this.config.get('JWT_REFRESH_EXPIRES_IN') ?? '30d');
    await this.prisma.refreshToken.create({
      data: {
        userId,
        tokenHash: hashValue(refreshToken),
        expiresAt: new Date(Date.now() + refreshExpiresInDays * 24 * 60 * 60 * 1000),
      },
    });

    return { accessToken, refreshToken };
  }

  private parseDaysFromExpiresIn(value: string): number {
    const match = /^(\d+)d$/.exec(value);
    return match ? Number(match[1]) : 30;
  }
}
