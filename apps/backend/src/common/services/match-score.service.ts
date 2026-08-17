import { Injectable } from '@nestjs/common';
import { Job, JobSeekerProfile } from '@prisma/client';

// Điểm phù hợp theo mục 19. V1 dùng rule-based, không phải AI/ML.
// Interface trả về giữ nguyên dù sau này thay bằng model học máy - không đổi contract API.
@Injectable()
export class MatchScoreService {
  computeScore(job: Job, seeker: JobSeekerProfile): number {
    let score = 0;
    let maxScore = 0;

    // Ngành nghề (weight 30)
    maxScore += 30;
    if (seeker.desiredCategoryId && seeker.desiredCategoryId === job.categoryId) {
      score += 30;
    }

    // Khu vực / khoảng cách (weight 25)
    maxScore += 25;
    if (seeker.latitude != null && seeker.longitude != null) {
      const distanceKm = this.haversineKm(seeker.latitude, seeker.longitude, job.latitude, job.longitude);
      if (distanceKm <= 1) score += 25;
      else if (distanceKm <= 3) score += 20;
      else if (distanceKm <= 5) score += 12;
      else if (distanceKm <= 10) score += 5;
    } else if (seeker.areaId === job.areaId) {
      score += 20;
    }

    // Ca làm (weight 15)
    maxScore += 15;
    if (seeker.shiftPreferences.some((s) => s === 'FLEXIBLE') || job.shifts.some((s) => seeker.shiftPreferences.includes(s))) {
      score += 15;
    }

    // Mức lương (weight 15)
    maxScore += 15;
    if (seeker.desiredSalaryMin != null && seeker.desiredSalaryMax != null && seeker.salaryUnit === job.salaryUnit) {
      const overlap = Math.min(seeker.desiredSalaryMax, job.salaryMax) - Math.max(seeker.desiredSalaryMin, job.salaryMin);
      if (overlap >= 0) score += 15;
    }

    // Kinh nghiệm (weight 10)
    maxScore += 10;
    if (job.requiredExperience === 'NOT_REQUIRED') score += 10;
    else if (seeker.experienceLevel !== 'NONE') score += 10;

    // Đi làm ngay (weight 5)
    maxScore += 5;
    if (seeker.isLookingNow && job.startUrgency === 'IMMEDIATE') score += 5;

    return Math.round((score / maxScore) * 100);
  }

  private haversineKm(lat1: number, lon1: number, lat2: number, lon2: number): number {
    const toRad = (deg: number) => (deg * Math.PI) / 180;
    const R = 6371;
    const dLat = toRad(lat2 - lat1);
    const dLon = toRad(lon2 - lon1);
    const a =
      Math.sin(dLat / 2) ** 2 + Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLon / 2) ** 2;
    const c = 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
    return R * c;
  }
}
