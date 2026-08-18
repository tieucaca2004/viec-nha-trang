import { Module } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JwtModule } from '@nestjs/jwt';
import { PassportModule } from '@nestjs/passport';
import { AuthController } from './auth.controller';
import { AuthService } from './auth.service';
import { JwtStrategy } from './jwt.strategy';
import { selectSmsProvider } from './sms-provider.factory';
import { ConsoleSmsProvider } from '../common/services/console-sms.provider';
import { EsmsProvider } from '../common/services/esms.provider';
import { SMS_PROVIDER } from '../common/services/tokens';

@Module({
  imports: [PassportModule, JwtModule.register({})],
  controllers: [AuthController],
  providers: [
    AuthService,
    JwtStrategy,
    ConsoleSmsProvider,
    EsmsProvider,
    {
      provide: SMS_PROVIDER,
      useFactory: selectSmsProvider,
      inject: [ConfigService, ConsoleSmsProvider, EsmsProvider],
    },
  ],
  exports: [AuthService],
})
export class AuthModule {}
