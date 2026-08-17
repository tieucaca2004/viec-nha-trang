import { Body, Controller, Get, Post, Put, UseGuards } from '@nestjs/common';
import { JwtAuthGuard } from '../common/guards/jwt-auth.guard';
import { RolesGuard } from '../common/guards/roles.guard';
import { Roles } from '../common/decorators/roles.decorator';
import { CurrentUser, AuthenticatedUser } from '../common/decorators/current-user.decorator';
import { EmployersService } from './employers.service';
import { UpsertEmployerProfileDto, CreateEmployerLocationDto } from './dto/employer.dto';

@UseGuards(JwtAuthGuard, RolesGuard)
@Controller('me/employer-profile')
export class EmployersController {
  constructor(private readonly employersService: EmployersService) {}

  @Get()
  getMyProfile(@CurrentUser() user: AuthenticatedUser) {
    return this.employersService.getMyProfile(user.userId);
  }

  @Roles('EMPLOYER')
  @Put()
  upsertMyProfile(@CurrentUser() user: AuthenticatedUser, @Body() dto: UpsertEmployerProfileDto) {
    return this.employersService.upsertMyProfile(user.userId, dto);
  }

  @Roles('EMPLOYER')
  @Get('locations')
  listMyLocations(@CurrentUser() user: AuthenticatedUser) {
    return this.employersService.listMyLocations(user.userId);
  }

  @Roles('EMPLOYER')
  @Post('locations')
  addLocation(@CurrentUser() user: AuthenticatedUser, @Body() dto: CreateEmployerLocationDto) {
    return this.employersService.addLocation(user.userId, dto);
  }
}
