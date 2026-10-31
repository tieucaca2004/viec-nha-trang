import { Module } from '@nestjs/common';
import { CommunityPostsService } from './community-posts.service';
import { CommunityPostsAdminController, CommunityPostsController } from './community-posts.controller';

@Module({
  controllers: [CommunityPostsController, CommunityPostsAdminController],
  providers: [CommunityPostsService],
  exports: [CommunityPostsService],
})
export class CommunityPostsModule {}
