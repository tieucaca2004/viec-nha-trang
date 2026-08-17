import { useState, type CSSProperties } from 'react';
import { useRouter } from 'next/router';
import { api, setToken, clearToken } from '../lib/api';

// Đăng nhập admin dùng chung cơ chế OTP với app (mục 5), chỉ khác là sau khi
// xác thực, trang kiểm tra tài khoản có vai trò ADMIN hay không trước khi cho vào CMS.
export default function LoginPage() {
  const router = useRouter();
  const [phone, setPhone] = useState('');
  const [code, setCode] = useState('');
  const [step, setStep] = useState<'phone' | 'otp'>('phone');
  const [error, setError] = useState<string | null>(null);
  const [loading, setLoading] = useState(false);

  const requestOtp = async () => {
    setLoading(true);
    setError(null);
    try {
      await api.post('/auth/otp/request', { phone });
      setStep('otp');
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  };

  const verifyOtp = async () => {
    setLoading(true);
    setError(null);
    try {
      const res = await api.post('/auth/otp/verify', { phone, code });
      setToken(res.accessToken);
      const me = await api.get('/me');
      if (!me.roles?.includes('ADMIN')) {
        clearToken();
        setError('Tài khoản này không có quyền admin.');
        return;
      }
      router.replace('/');
    } catch (e) {
      setError((e as Error).message);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div style={{ display: 'flex', minHeight: '100vh', alignItems: 'center', justifyContent: 'center', fontFamily: 'system-ui, sans-serif' }}>
      <div style={{ width: 360, padding: 24, border: '1px solid #e2e8f0', borderRadius: 8 }}>
        <h1 style={{ fontSize: 20, marginBottom: 16 }}>VIỆC NHA TRANG - Admin</h1>
        {step === 'phone' ? (
          <>
            <input
              placeholder="Số điện thoại admin"
              value={phone}
              onChange={(e) => setPhone(e.target.value)}
              style={{ width: '100%', padding: 10, marginBottom: 12, border: '1px solid #cbd5e1', borderRadius: 6 }}
            />
            <button onClick={requestOtp} disabled={loading} style={buttonStyle}>
              Gửi mã OTP
            </button>
          </>
        ) : (
          <>
            <input
              placeholder="Mã OTP"
              value={code}
              onChange={(e) => setCode(e.target.value)}
              style={{ width: '100%', padding: 10, marginBottom: 12, border: '1px solid #cbd5e1', borderRadius: 6 }}
            />
            <button onClick={verifyOtp} disabled={loading} style={buttonStyle}>
              Đăng nhập
            </button>
          </>
        )}
        {error && <p style={{ color: '#dc2626', marginTop: 12 }}>{error}</p>}
      </div>
    </div>
  );
}

const buttonStyle: CSSProperties = {
  width: '100%',
  padding: 10,
  background: '#0f172a',
  color: '#fff',
  border: 'none',
  borderRadius: 6,
  cursor: 'pointer',
};
