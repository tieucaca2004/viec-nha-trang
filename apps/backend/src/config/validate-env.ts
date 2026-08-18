/// Xác thực sớm các biến môi trường THẬT SỰ bắt buộc lúc khởi động app - fail-fast với thông
/// báo rõ tên biến còn thiếu, thay vì để lỗi mơ hồ như "JwtStrategy requires a secret or key"
/// (passport-jwt) xuất hiện muộn khi JwtStrategy được khởi tạo. Không bao giờ log giá trị thật.
const REQUIRED_ENV_VARS = ['JWT_ACCESS_SECRET', 'JWT_REFRESH_SECRET'] as const;

export function validateEnv(config: Record<string, unknown>): Record<string, unknown> {
  const missing = REQUIRED_ENV_VARS.filter((key) => {
    const value = config[key];
    return typeof value !== 'string' || value.trim().length === 0;
  });
  if (missing.length > 0) {
    throw new Error(
      `Thiếu hoặc rỗng biến môi trường bắt buộc: ${missing.join(', ')}. ` +
        'Kiểm tra file .env/.env.staging (hoặc env_file của container) - biến này phải có giá trị THẬT, không được để trống.',
    );
  }
  return config;
}
