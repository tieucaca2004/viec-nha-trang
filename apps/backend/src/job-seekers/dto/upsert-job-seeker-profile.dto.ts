import { Type } from 'class-transformer';
import {
  IsArray,
  IsBoolean,
  IsDateString,
  IsEnum,
  IsInt,
  IsLatitude,
  IsLongitude,
  IsOptional,
  IsString,
  Min,
} from 'class-validator';
import { ExperienceLevel, SalaryUnit, ShiftPreference } from '@prisma/client';

// Hồ sơ ứng viên tối giản (mục 11): họ tên, SĐT (đã có qua auth), khu vực,
// ngành nghề mong muốn, kinh nghiệm, ca có thể làm, mức lương mong muốn. CV không bắt buộc.
export class UpsertJobSeekerProfileDto {
  @IsString()
  fullName!: string;

  @IsOptional()
  @IsString()
  avatarUrl?: string;

  @IsOptional()
  @IsString()
  areaId?: string;

  @IsOptional()
  @Type(() => Number)
  @IsLatitude()
  latitude?: number;

  @IsOptional()
  @Type(() => Number)
  @IsLongitude()
  longitude?: number;

  @IsOptional()
  @IsString()
  desiredCategoryId?: string;

  // Ngày sinh (đặc tả §2) - nhận string ISO date "YYYY-MM-DD" từ frontend, validate ở service
  // (không cho ngày tương lai) vì class-validator không có sẵn kiểm tra "không tương lai" động
  // theo thời điểm request (MaxDate chỉ nhận mốc cố định lúc khai báo class).
  @IsOptional()
  @IsDateString()
  dateOfBirth?: string;

  @IsOptional()
  @IsEnum(ExperienceLevel)
  experienceLevel?: ExperienceLevel;

  @IsOptional()
  @IsArray()
  @IsString({ each: true })
  skills?: string[];

  @IsOptional()
  @IsArray()
  @IsEnum(ShiftPreference, { each: true })
  shiftPreferences?: ShiftPreference[];

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  desiredSalaryMin?: number;

  @IsOptional()
  @Type(() => Number)
  @IsInt()
  @Min(0)
  desiredSalaryMax?: number;

  @IsOptional()
  @IsEnum(SalaryUnit)
  salaryUnit?: SalaryUnit;

  @IsOptional()
  @IsBoolean()
  isLookingNow?: boolean;

  @IsOptional()
  @IsBoolean()
  isSeeking?: boolean;
}
