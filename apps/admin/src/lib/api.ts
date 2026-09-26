const API_BASE_URL = process.env.NEXT_PUBLIC_API_BASE_URL ?? 'http://localhost:3000/api/v1';

function getToken(): string | null {
  if (typeof window === 'undefined') return null;
  return window.localStorage.getItem('adminAccessToken');
}

export function setToken(token: string) {
  window.localStorage.setItem('adminAccessToken', token);
}

export function clearToken() {
  window.localStorage.removeItem('adminAccessToken');
}

export function isLoggedIn(): boolean {
  return !!getToken();
}

async function request(path: string, options: RequestInit = {}) {
  const token = getToken();
  const res = await fetch(`${API_BASE_URL}${path}`, {
    ...options,
    headers: {
      'Content-Type': 'application/json',
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(options.headers ?? {}),
    },
  });
  if (!res.ok) {
    // Access token hết hạn sau JWT_ACCESS_EXPIRES_IN (15 phút) và CMS không refresh - nếu không xử lý,
    // mọi trang hiện bảng rỗng (lỗi bị nuốt) và thao tác thất bại âm thầm. Đưa admin về đăng nhập lại.
    if (res.status === 401 && token) {
      clearToken();
      if (window.location.pathname !== '/login') {
        window.location.replace('/login');
      }
    }
    const body = await res.json().catch(() => ({}));
    throw new Error(body.message ?? `Lỗi ${res.status}`);
  }
  if (res.status === 204) return null;
  return res.json();
}

export const api = {
  get: (path: string) => request(path),
  post: (path: string, body?: unknown) => request(path, { method: 'POST', body: body ? JSON.stringify(body) : undefined }),
  patch: (path: string, body?: unknown) => request(path, { method: 'PATCH', body: body ? JSON.stringify(body) : undefined }),
};
