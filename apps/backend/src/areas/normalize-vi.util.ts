// Chuẩn hoá tên tiếng Việt để search không phân biệt dấu/hoa-thường mà không cần extension
// `unaccent` của Postgres (staging Cloud SQL/managed Postgres có thể không cho cài extension).
// "Vĩnh Hải" -> "vinh hai". Dùng cho cả AreaAlias.normalizedName khi seed và query khi search.
export function normalizeVietnamese(input: string): string {
  return input
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd')
    .replace(/Đ/g, 'D')
    .toLowerCase()
    .trim()
    .replace(/\s+/g, ' ');
}
