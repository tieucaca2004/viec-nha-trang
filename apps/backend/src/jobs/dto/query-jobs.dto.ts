import { Transform, Type } from 'class-transformer';
import { IsBoolean, IsEnum, IsInt, IsLatitude, IsLongitude, IsNumber, IsOptional, IsString, Max, Min } from 'class-validator';
import { EmploymentType, SalaryUnit, ShiftPreference, StartUrgency } from '@prisma/client';

export enum JobSortBy {
  DISTANCE = 'distance',
  NEWEST = 'newest',
  SALARY = 'salary',
}

// Bộ lọc theo mục 9: khu vực/bán kính, loại việc, ca, lương, từ khóa.
export class QueryJobsDto {
  @IsOptional()
  @IsString()
  keyword?: string;

  @IsOptional()
  @IsString()
  categoryId?: string;

  @IsOptional()
  @IsString()
  areaId?: string;

  @IsOptional()
  @IsString()
  cityId?: string;

  @IsOptional()
  @Type(() => Number)
  @IsLatitude()
  latitude?: number;

  @IsOptional()
  @Type(() => Number)
  @IsLongitude()
  longitude?: number;

  @IsOptional()
  @Type(() => Number)
  @Min(0.5)
  @Max(50)
  radiusKm?: number;

  @IsOptional()
  @IsEnum(EmploymentType)
  employmentType?: EmploymentType;

  @IsOptional()
  @IsEnum(ShiftPreference)
  shift?: ShiftPreference;

  @IsOptional()
  @IsEnum(SalaryUnit)
  salaryUnit?: SalaryUnit;

  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  salaryMin?: number;

  // Bổ sung sửa lỗi High #9 (FULL AUDIT): mobile filter sheet cần lọc theo khoảng lương
  // min/max, nhưng backend trước đó chỉ có salaryMin (chặn dưới). Thêm salaryMax optional,
  // backward-compatible, không đổi hành vi field salaryMin hiện có.
  @IsOptional()
  @Type(() => Number)
  @IsNumber()
  salaryMax?: number;

  @IsOptional()
  @Transform(({ value }) => value === true || value === 'true')
  @IsBoolean()
  isUrgent?: boolean;

  @IsOptional()
  @IsEnum(JobSortBy)
  sortBy?: JobSortBy;

  // Bổ sung Phase 3: mobile filter "Khi nào cần người" (đặc tả §10) - phát hiện API gap
  // khi implement bộ lọc, thêm field optional này, không đổi hành vi các field khác.
  @IsOptional()
  @IsEnum(StartUrgency)
  startUrgency?: StartUrgency;

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
