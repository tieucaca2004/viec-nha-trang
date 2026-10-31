import { Body, Controller, Get, Param, Patch, Query, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { CommunityPostsService } from './community-posts.service';
import {
  AdminQueryCommunityPostsDto,
  ModerateCommunityPostDto,
  QueryCommunityPostsDto,
} from './community-posts.dto';

// Công khai: chỉ trả bài đã duyệt, còn hạn, và KHÔNG chứa PII (xem service).
@ApiTags('Community Posts')
@Controller('community-posts')
export class CommunityPostsController {
  constructor(private readonly communityPostsService: CommunityPostsService) {}

  @Get()
  list(@Query() query: QueryCommunityPostsDto) {
    return this.communityPostsService.listPublic(query);
  }

  @Get(':id')
  findOne(@Param('id') id: string) {
    return this.communityPostsService.findPublicOne(id);
  }
}

// Quản trị: bắt buộc JWT + role ADMIN (server-side, không chỉ ẩn nút trên UI).
@ApiTags('Admin Community Posts')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Roles('ADMIN')
@Controller('admin/community-posts')
export class CommunityPostsAdminController {
  constructor(private readonly communityPostsService: CommunityPostsService) {}

  @Get()
  list(@Query() query: AdminQueryCommunityPostsDto) {
    return this.communityPostsService.listAdmin(query);
  }

  @Get('stats')
  stats() {
    return this.communityPostsService.stats();
  }

  @Patch(':id')
  moderate(
    @CurrentUser() user: AuthenticatedUser,
    @Param('id') id: string,
    @Body() dto: ModerateCommunityPostDto,
  ) {
    return this.communityPostsService.moderate(user.userId, id, dto.status, dto.note);
  }
}
