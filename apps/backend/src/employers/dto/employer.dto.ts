import { Type } from 'class-transformer';
import { IsOptional, IsString } from 'class-validator';

export class UpsertEmployerProfileDto {
  @IsString()
  businessName!: string;

  @IsOptional()
  @IsString()
  logoUrl?: string;

  @IsOptional()
  @IsString()
  description?: string;
}

export class CreateEmployerLocationDto {
  @IsString()
  name!: string;

  @IsString()
  address!: string;

  @IsString()
  cityId!: string;

  @IsString()
  areaId!: string;

  @Type(() => Number)
  latitude!: number;

  @Type(() => Number)
  longitude!: number;

  @IsOptional()
  @IsString()
  phone?: string;
}
