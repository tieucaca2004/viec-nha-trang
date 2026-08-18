import { Controller, Get } from '@nestjs/common';
import { SkipThrottle } from '@nestjs/throttler';

/// Health check đơn giản, không phụ thuộc DB - dùng cho Docker healthcheck/load balancer,
/// không phải đặc tả sản phẩm (đặc tả §37: cần verify staging deploy trước khi mở port).
@SkipThrottle()
@Controller('health')
export class HealthController {
  @Get()
  check() {
    return { status: 'ok' };
  }
}
