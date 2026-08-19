import { Injectable } from '@nestjs/common';
import { DedupeGroup, NormalizedJob } from './types';

// Deduplicator (đặc tả Phần 8): gom các NormalizedJob trùng nhau từ nhiều nguồn thành 1 nhóm
// canonical + duplicates - KHÔNG xoá provenance của bản duplicate, chỉ đánh dấu nó trỏ về
// canonical (Job.duplicateOfId) để admin vẫn truy được nguồn gốc từng bản.
const SIMILARITY_THRESHOLD = 0.6;

@Injectable()
export class DeduplicatorService {
  group(jobs: NormalizedJob[]): DedupeGroup[] {
    const groups: DedupeGroup[] = [];

    for (const job of jobs) {
      const existingGroup = groups.find((g) => this.areDuplicates(g.canonical, job));
      if (existingGroup) {
        existingGroup.duplicates.push(job);
      } else {
        groups.push({ canonical: job, duplicates: [] });
      }
    }

    return groups;
  }

  areDuplicates(a: NormalizedJob, b: NormalizedJob): boolean {
    // Cùng nguồn + cùng sourceJobId => chắc chắn là cùng 1 tin (vd crawl lại nguồn cũ).
    if (a.sourceName === b.sourceName && a.sourceJobId && a.sourceJobId === b.sourceJobId) return true;

    // Cùng canonical URL (bỏ query string/hash/trailing slash) => cùng 1 tin dù sourceJobId khác định dạng.
    const urlA = canonicalUrl(a.sourceUrl);
    const urlB = canonicalUrl(b.sourceUrl);
    if (urlA && urlB && urlA === urlB) return true;

    return this.similarityScore(a, b) >= SIMILARITY_THRESHOLD;
  }

  // Điểm tương đồng 0-1 dựa trên: title, employer, location, lương, mô tả (Jaccard trên token).
  similarityScore(a: NormalizedJob, b: NormalizedJob): number {
    const signals: number[] = [];

    signals.push(tokenJaccard(a.title, b.title));

    if (a.companyName && b.companyName) {
      signals.push(normalizeText(a.companyName) === normalizeText(b.companyName) ? 1 : 0);
    }

    if (a.location?.areaSlug && b.location?.areaSlug) {
      signals.push(a.location.areaSlug === b.location.areaSlug ? 1 : 0);
    } else if (a.location?.citySlug && b.location?.citySlug) {
      signals.push(a.location.citySlug === b.location.citySlug ? 1 : 0);
    }

    if (a.salary && b.salary) {
      const overlap = rangeOverlap(a.salary.min, a.salary.max, b.salary.min, b.salary.max);
      signals.push(overlap ? 1 : 0);
    }

    if (a.description && b.description) {
      signals.push(tokenJaccard(a.description, b.description));
    }

    if (signals.length === 0) return 0;
    return signals.reduce((sum, s) => sum + s, 0) / signals.length;
  }
}

function normalizeText(text: string): string {
  return text
    .toLowerCase()
    .normalize('NFC')
    .replace(/[^\p{L}\p{N}\s]/gu, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function tokenJaccard(a: string, b: string): number {
  const setA = new Set(normalizeText(a).split(' ').filter(Boolean));
  const setB = new Set(normalizeText(b).split(' ').filter(Boolean));
  if (setA.size === 0 || setB.size === 0) return 0;
  let intersection = 0;
  for (const token of setA) if (setB.has(token)) intersection += 1;
  const union = setA.size + setB.size - intersection;
  return union === 0 ? 0 : intersection / union;
}

function rangeOverlap(aMin: number, aMax: number, bMin: number, bMax: number): boolean {
  return aMin <= bMax && bMin <= aMax;
}

function canonicalUrl(url?: string): string | null {
  if (!url) return null;
  try {
    const parsed = new URL(url);
    return `${parsed.hostname}${parsed.pathname}`.replace(/\/$/, '').toLowerCase();
  } catch {
    return url.trim().toLowerCase().replace(/\/$/, '');
  }
}
