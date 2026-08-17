import { Body, Controller, Get, Put, UseGuards } from '@nestjs/common';
import { ApiBearerAuth, ApiTags } from '@nestjs/swagger';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { JobSeekersService } from './job-seekers.service';
import { UpsertJobSeekerProfileDto } from './dto/upsert-job-seeker-profile.dto';

@ApiTags('Job Seekers')
@ApiBearerAuth()
@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('me/job-seeker-profile')
export class JobSeekersController {
  constructor(private readonly jobSeekersService: JobSeekersService) {}

  @Get()
  getMyProfile(@CurrentUser() user: AuthenticatedUser) {
    return this.jobSeekersService.getMyProfile(user.userId);
  }

  @Roles('JOB_SEEKER')
  @Put()
  upsertMyProfile(@CurrentUser() user: AuthenticatedUser, @Body() dto: UpsertJobSeekerProfileDto) {
    return this.jobSeekersService.upsertMyProfile(user.userId, dto);
  }
}
