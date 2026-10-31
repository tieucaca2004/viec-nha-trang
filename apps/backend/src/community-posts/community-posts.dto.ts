import { Type } from 'class-transformer';
import { IsEnum, IsInt, IsOptional, IsString, Max, Min } from 'class-validator';
import { CommunityPostStatus, CommunityPostType } from '@prisma/client';

export class QueryCommunityPostsDto {
  @IsOptional()
  @IsEnum(CommunityPostType)
  type?: CommunityPostType;

  @IsOptional()
  @IsString()
  industry?: string;

  @IsOptional()
  @IsString()
  location?: string;

  @IsOptional()
  @IsString()
  employmentType?: string;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  minSalary?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  offset?: number;
}

export class AdminQueryCommunityPostsDto {
  @IsOptional()
  @IsEnum(CommunityPostStatus)
  status?: CommunityPostStatus;

  @IsOptional()
  @IsEnum(CommunityPostType)
  type?: CommunityPostType;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(1)
  @Max(50)
  limit?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  offset?: number;
}

export class ModerateCommunityPostDto {
  @IsEnum(CommunityPostStatus)
  status!: CommunityPostStatus;

  @IsOptional()
  @IsString()
  note?: string;
}
