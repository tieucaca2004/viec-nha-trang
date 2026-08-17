import { Injectable, UnauthorizedException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { PrismaService } from '../prisma/prisma.service';

interface JwtPayload {
  sub: string;
  roles: string[];
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(
    config: ConfigService,
    private readonly prisma: PrismaService,
  ) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>('JWT_ACCESS_SECRET'),
    });
  }

  // Kết quả trả về ở đây trở thành request.user - đây là nguồn sự thật duy nhất
  // cho userId/roles (đặc tả mục 32). Roles đọc lại từ DB thay vì tin claim trong token:
  // token cũ vẫn hợp lệ (chưa hết hạn) sau khi user đổi vai trò hoặc bị khóa, nên guard
  // phải phản ánh trạng thái hiện tại, không phải trạng thái tại thời điểm đăng nhập.
  async validate(payload: JwtPayload): Promise<AuthenticatedUser> {
    const user = await this.prisma.user.findUnique({
      where: { id: payload.sub },
      select: { id: true, roles: true, isBanned: true, deletedAt: true },
    });
    if (!user || user.isBanned || user.deletedAt) {
      throw new UnauthorizedException('Tài khoản không hợp lệ hoặc đã bị khóa.');
    }
    return { userId: user.id, roles: user.roles };
  }
}
