import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { PassportStrategy } from '@nestjs/passport';
import { ExtractJwt, Strategy } from 'passport-jwt';
import { AuthenticatedUser } from '../common/decorators/current-user.decorator';

interface JwtPayload {
  sub: string;
  roles: string[];
}

@Injectable()
export class JwtStrategy extends PassportStrategy(Strategy) {
  constructor(config: ConfigService) {
    super({
      jwtFromRequest: ExtractJwt.fromAuthHeaderAsBearerToken(),
      ignoreExpiration: false,
      secretOrKey: config.get<string>('JWT_ACCESS_SECRET'),
    });
  }

  // Kết quả trả về ở đây trở thành request.user - đây là nguồn sự thật duy nhất
  // cho userId/roles, client không thể tự khai (đặc tả mục 32).
  async validate(payload: JwtPayload): Promise<AuthenticatedUser> {
    return { userId: payload.sub, roles: payload.roles };
  }
}
