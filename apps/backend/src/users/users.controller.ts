import { Body, Controller, Get, Patch, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { IsString } from 'class-validator';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { UsersService } from './users.service';

class SetPushTokenDto {
  @IsString()
  pushToken!: string;
}

@ApiTags('Me')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard)
@Controller('me')
export class UsersController {
  constructor(private readonly usersService: UsersService) {}

  @Get()
  getMe(@CurrentUser() user: AuthenticatedUser) {
    return this.usersService.getMe(user.userId);
  }

  // Cho phép user thêm vai trò (vd job_seeker muốn đăng tuyển) mà không tạo tài khoản mới (mục 5).
  @Patch('roles')
  addEmployerRole(@CurrentUser() user: AuthenticatedUser, @Body('role') role: 'JOB_SEEKER' | 'EMPLOYER') {
    return this.usersService.addRole(user.userId, role);
  }

  // Mobile app gọi sau khi có FCM device token, để backend biết gửi push tới đâu (mục 9 docs/PLAN.md).
  @Patch('push-token')
  setPushToken(@CurrentUser() user: AuthenticatedUser, @Body() dto: SetPushTokenDto) {
    return this.usersService.setPushToken(user.userId, dto.pushToken);
  }
}
