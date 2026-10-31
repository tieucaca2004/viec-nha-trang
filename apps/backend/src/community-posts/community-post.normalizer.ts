// Chuẩn hoá dữ liệu bài Facebook đã thu thập (posts.json) thành bản ghi CommunityPost.
// Hàm THUẦN (không I/O) để test dễ và để importer tái dùng. KHÔNG bịa dữ liệu: trường nào
// nguồn không có thì trả null, không suy đoán tên công ty / địa chỉ / mức lương.

export type CommunityPostTypeValue = 'HIRING' | 'JOB_SEEKER';

/** Một phần tử thô trong posts.json (chỉ các trường chúng ta dùng). */
export interface RawFacebookPost {
  category?: string | null;
  post_id?: string | null;
  post_url?: string | null;
  group_name?: string | null;
  group_url?: string | null;
  job_title?: string | null;
  industry?: string | null;
  employer_name?: string | null;
  work_location?: string | null;
  salary_min?: number | string | null;
  salary_max?: number | string | null;
  salary_currency?: string | null;
  salary_period?: string | null;
  salary_text_original?: string | null;
  employment_type?: string | null;
  work_schedule?: string | null;
  experience_required?: string | null;
  benefits?: string | null;
  contact_method?: string | null;
  contact_public?: boolean | null;
  contacts?: unknown;
  data_quality?: string | null;
  duplicate_of?: unknown;
  posted_at?: string | null;
  collection_timestamp?: string | null;
  post_text?: string | null;
}

export interface NormalizedCommunityPost {
  source: 'FACEBOOK';
  sourceName: string;
  sourcePostId: string | null;
  sourceUrl: string;
  sourceGroupName: string | null;
  sourceGroupUrl: string | null;
  postType: CommunityPostTypeValue;
  title: string | null;
  body: string;
  industry: string | null;
  employerName: string | null;
  workLocation: string | null;
  salaryMin: number | null;
  salaryMax: number | null;
  salaryCurrency: string | null;
  salaryPeriod: string | null;
  salaryTextOriginal: string | null;
  employmentType: string | null;
  workSchedule: string | null;
  experienceRequired: string | null;
  benefits: string | null;
  contactMethod: string | null;
  contactPublic: boolean;
  contactsRaw: unknown;
  dataQuality: string | null;
  duplicateOfId: string | null;
  postedAt: Date | null;
  collectedAt: Date | null;
}

/** Phân loại: chỉ HIRING/JOB_SEEKER mới nhập; IRRELEVANT (và giá trị lạ) bị loại. */
export function classify(category?: string | null): CommunityPostTypeValue | null {
  const c = (category ?? '').trim().toUpperCase();
  if (c === 'HIRING') return 'HIRING';
  if (c === 'JOB_SEEKER') return 'JOB_SEEKER';
  return null;
}

/** Trim + gộp khoảng trắng; rỗng -> null. */
export function cleanText(value?: string | null): string | null {
  if (value == null) return null;
  const t = value.replace(/\s+/g, ' ').trim();
  return t.length > 0 ? t : null;
}

// Bỏ tiền tố địa điểm hay gặp trong bài: "Địa chỉ :", "Địa điểm:", "Địa điểm làm việc:"...
const LOCATION_PREFIX = /^\s*(địa\s+chỉ|địa\s+điểm(?:\s+làm\s+việc)?|nơi\s+làm\s+việc)\s*[:：]\s*/i;
export function stripLocationPrefix(value?: string | null): string | null {
  const t = cleanText(value);
  if (!t) return null;
  const stripped = t.replace(LOCATION_PREFIX, '').trim();
  return stripped.length > 0 ? stripped : null;
}

/** Số nguyên an toàn; "12", "12,5", "12 tr" -> 12; null/không phải số -> null. */
export function toInt(value?: number | string | null): number | null {
  if (value == null || value === '') return null;
  if (typeof value === 'number') return Number.isFinite(value) ? Math.round(value) : null;
  const cleaned = String(value).replace(/[^\d.-]/g, '');
  if (cleaned === '') return null; // "abc"/"tr" -> rỗng -> không có số, KHÔNG trả 0
  const n = Number(cleaned);
  return Number.isFinite(n) ? Math.round(n) : null;
}

// Chuẩn hoá hình thức làm việc về nhãn cố định khi nhận diện được; ngược lại giữ nguyên nhãn gốc.
export function normalizeEmploymentType(value?: string | null): string | null {
  const t = cleanText(value);
  if (!t) return null;
  const l = t.toLowerCase();
  if (l.includes('full')) return 'FULL_TIME';
  if (l.includes('part')) return 'PART_TIME';
  return t;
}

const PHONE_RE = /(?:\+?84|0)(?:\d[\s.-]?){8,9}\d/g;
const EMAIL_RE = /[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}/g;

/** Ẩn SĐT/email trong nội dung công khai (dùng cho bài người tìm việc). */
export function redactPii(text: string | null | undefined): string | null {
  if (!text) return null;
  return text.replace(EMAIL_RE, '[email đã ẩn]').replace(PHONE_RE, '[SĐT đã ẩn]');
}

export function parseDate(value?: string | null): Date | null {
  if (!value) return null;
  const d = new Date(value);
  return Number.isNaN(d.getTime()) ? null : d;
}

/**
 * Chuẩn hoá 1 bài thô. Trả null khi: không phải HIRING/JOB_SEEKER, thiếu post_url (khóa chống
 * trùng), hoặc không có nội dung (body). Importer dùng null để đếm "bỏ qua".
 */
export function normalizePost(raw: RawFacebookPost): NormalizedCommunityPost | null {
  const postType = classify(raw.category);
  if (!postType) return null;

  const sourceUrl = cleanText(raw.post_url);
  if (!sourceUrl) return null;

  const body = (raw.post_text ?? '').trim();
  if (!body) return null;

  return {
    source: 'FACEBOOK',
    sourceName: 'facebook',
    sourcePostId: cleanText(raw.post_id),
    sourceUrl,
    sourceGroupName: cleanText(raw.group_name),
    sourceGroupUrl: cleanText(raw.group_url),
    postType,
    title: cleanText(raw.job_title),
    body,
    industry: cleanText(raw.industry),
    employerName: cleanText(raw.employer_name),
    workLocation: stripLocationPrefix(raw.work_location),
    salaryMin: toInt(raw.salary_min),
    salaryMax: toInt(raw.salary_max),
    salaryCurrency: cleanText(raw.salary_currency),
    salaryPeriod: cleanText(raw.salary_period),
    salaryTextOriginal: cleanText(raw.salary_text_original),
    employmentType: normalizeEmploymentType(raw.employment_type),
    workSchedule: cleanText(raw.work_schedule),
    experienceRequired: cleanText(raw.experience_required),
    benefits: cleanText(raw.benefits),
    contactMethod: cleanText(raw.contact_method),
    contactPublic: raw.contact_public === true,
    contactsRaw: raw.contacts ?? null,
    dataQuality: cleanText(raw.data_quality),
    duplicateOfId: null,
    postedAt: parseDate(raw.posted_at),
    collectedAt: parseDate(raw.collection_timestamp),
  };
}

export interface PublicCommunityPost {
  id: string;
  postType: CommunityPostTypeValue;
  title: string | null;
  body: string | null;
  industry: string | null;
  employerName: string | null;
  workLocation: string | null;
  salaryMin: number | null;
  salaryMax: number | null;
  salaryCurrency: string | null;
  salaryPeriod: string | null;
  salaryTextOriginal: string | null;
  employmentType: string | null;
  workSchedule: string | null;
  experienceRequired: string | null;
  benefits: string | null;
  contactMethod: string | null;
  postedAt: Date | null;
  sourceType: 'FACEBOOK';
  sourceGroupName: string | null;
  sourceUrl: string;
  dataQuality: string | null;
}

// Trường tối thiểu của CommunityPost mà projection công khai cần (để test không cần Prisma).
export interface CommunityPostRowLike {
  id: string;
  postType: CommunityPostTypeValue;
  title: string | null;
  body: string | null;
  industry: string | null;
  employerName: string | null;
  workLocation: string | null;
  salaryMin: number | null;
  salaryMax: number | null;
  salaryCurrency: string | null;
  salaryPeriod: string | null;
  salaryTextOriginal: string | null;
  employmentType: string | null;
  workSchedule: string | null;
  experienceRequired: string | null;
  benefits: string | null;
  contactMethod: string | null;
  postedAt: Date | null;
  sourceGroupName: string | null;
  sourceUrl: string;
  dataQuality: string | null;
}

/**
 * Chiếu ra dữ liệu CÔNG KHAI: KHÔNG bao giờ chứa contactsRaw / contactPublic / PII.
 * Với JOB_SEEKER, ẩn SĐT/email trong body (bài cá nhân). Với HIRING, body là nội dung tuyển
 * dụng công khai (liên hệ doanh nghiệp), nhưng vẫn không trả contactsRaw.
 */
export function toPublicCommunityPost(row: CommunityPostRowLike): PublicCommunityPost {
  const body = row.postType === 'JOB_SEEKER' ? redactPii(row.body) : row.body;
  return {
    id: row.id,
    postType: row.postType,
    title: row.title,
    body,
    industry: row.industry,
    employerName: row.employerName,
    workLocation: row.workLocation,
    salaryMin: row.salaryMin,
    salaryMax: row.salaryMax,
    salaryCurrency: row.salaryCurrency,
    salaryPeriod: row.salaryPeriod,
    salaryTextOriginal: row.salaryTextOriginal,
    employmentType: row.employmentType,
    workSchedule: row.workSchedule,
    experienceRequired: row.experienceRequired,
    benefits: row.benefits,
    contactMethod: row.contactMethod,
    postedAt: row.postedAt,
    sourceType: 'FACEBOOK',
    sourceGroupName: row.sourceGroupName,
    sourceUrl: row.sourceUrl,
    dataQuality: row.dataQuality,
  };
}
