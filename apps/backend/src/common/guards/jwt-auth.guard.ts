import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

// Mọi endpoint cần đăng nhập đi qua guard này; token được verify ở JwtStrategy.
// Client không bao giờ được tự khai userId/roles - luôn lấy từ payload đã ký server-side.
@Injectable()
export class JwtAuthGuard extends AuthGuard('jwt') {}
