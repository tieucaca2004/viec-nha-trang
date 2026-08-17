// passwordHash không bao giờ được trả về qua API, kể cả cho admin (mục 32/33: privacy).
// Dùng select tường minh này ở mọi nơi trả về User thay vì trả nguyên model.
export const SAFE_USER_SELECT = {
  id: true,
  phone: true,
  email: true,
  roles: true,
  authProvider: true,
  isPhoneVerified: true,
  isActive: true,
  isBanned: true,
  bannedReason: true,
  lastLoginAt: true,
  createdAt: true,
  updatedAt: true,
  deletedAt: true,
} as const;
