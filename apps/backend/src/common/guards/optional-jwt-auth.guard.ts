import { Injectable } from '@nestjs/common';
import { AuthGuard } from '@nestjs/passport';

// Dùng cho endpoint public nhưng muốn biết người gọi là ai NẾU có đăng nhập (vd GET /jobs/:id -
// chủ tin/admin cần xem được job không ACTIVE, người ẩn danh thì không). Không throw khi thiếu
// token hoặc token không hợp lệ - request.user chỉ đơn giản là undefined, khác JwtAuthGuard bắt buộc.
@Injectable()
export class OptionalJwtAuthGuard extends AuthGuard('jwt') {
  handleRequest<TUser = unknown>(_err: unknown, user: TUser): TUser {
    return user;
  }
}
