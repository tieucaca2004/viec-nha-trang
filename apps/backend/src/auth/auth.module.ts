import { Module } from '@nestjs/common';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';
import { ConsoleSmsProvider } from '../common/services/console-sms.provider';
import { SMS_PROVIDER } from '../common/services/tokens';

@Module({
  imports: [PassportModule, JwtModule.register({})],
  controllers: [AuthController],
  providers: [AuthService, JwtStrategy, { provide: SMS_PROVIDER, useClass: ConsoleSmsProvider }],
  exports: [AuthService],
})
export class AuthModule {}
