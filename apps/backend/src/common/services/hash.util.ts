import { randomBytes, scryptSync, timingSafeEqual } from 'crypto';

// Dùng scrypt (built-in Node crypto) để không phải thêm dependency ngoài cho hashing
// OTP code và refresh token. Đủ an toàn cho các giá trị ngắn hạn, có TTL.
export function hashValue(value: string): string {
  const salt = randomBytes(16).toString('hex');
  const derived = scryptSync(value, salt, 64).toString('hex');
  return `${salt}:${derived}`;
}

export function verifyHash(value: string, stored: string): boolean {
  const [salt, derivedHex] = stored.split(':');
  if (!salt || !derivedHex) return false;
  const derived = scryptSync(value, salt, 64);
  const storedBuf = Buffer.from(derivedHex, 'hex');
  if (derived.length !== storedBuf.length) return false;
  return timingSafeEqual(derived, storedBuf);
}

export function generateOtpCode(): string {
  return String(Math.floor(100000 + Math.random() * 900000));
}
