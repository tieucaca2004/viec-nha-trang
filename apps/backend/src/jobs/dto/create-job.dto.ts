import { Type } from 'class-transformer';
import {
  ArrayNotEmpty,
  IsArray,
  IsBoolean,
  IsEnum,
  IsInt,
  IsOptional,
  IsString,
  Min,
} from 'class-validator';
import {
  EmploymentType,
  RequiredExperience,
  SalaryUnit,
  ShiftPreference,
  StartUrgency,
} from '@prisma/client';

// Trường tương ứng các bước wizard đăng tin (mục 13). Lương là bắt buộc (mục 21).
export class CreateJobDto {
  @IsString()
  employerLocationId!: string;

  @IsString()
  categoryId!: string;

  @IsString()
  title!: string;

  @IsOptional()
  @IsString()
  description?: string;

  @IsOptional()
  @IsString()
  requirements?: string;

  @IsOptional()
  @IsString()
  benefits?: string;

  @Type(() => Number)
  @IsInt()
  @Min(1)
  headcount!: number;

  @IsEnum(EmploymentType)
  employmentType!: EmploymentType;

  @IsArray()
  @ArrayNotEmpty()
  @IsEnum(ShiftPreference, { each: true })
  shifts!: ShiftPreference[];

  @IsOptional()
  @IsString()
  shiftStartTime?: string;

  @IsOptional()
  @IsString()
  shiftEndTime?: string;

  @Type(() => Number)
  @IsInt()
  @Min(0)
  salaryMin!: number;

  @Type(() => Number)
  @IsInt()
  @Min(0)
  salaryMax!: number;

  @IsEnum(SalaryUnit)
  salaryUnit!: SalaryUnit;

  @IsOptional()
  @IsEnum(StartUrgency)
  startUrgency?: StartUrgency;

  @IsOptional()
  @IsEnum(RequiredExperience)
  requiredExperience?: RequiredExperience;

  @IsOptional()
  @IsBoolean()
  isUrgent?: boolean;
}

export class UpdateJobDto extends CreateJobDto {}
