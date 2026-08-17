import Link from 'next/link';
import { useRouter } from 'next/router';
import { ReactNode, useEffect } from 'react';
import { clearToken, isLoggedIn } from '../lib/api';

const NAV_ITEMS = [
  { href: '/', label: 'Dashboard' },
  { href: '/users', label: 'Users' },
  { href: '/employers', label: 'Employers' },
  { href: '/jobs', label: 'Jobs' },
  { href: '/applications', label: 'Applications' },
  { href: '/reports', label: 'Reports' },
  { href: '/categories', label: 'Categories' },
  { href: '/areas', label: 'Areas' },
];

// Admin CMS tối thiểu theo mục 29: Users, Employers, Jobs, Applications, Reports,
// Categories, Areas, Verification (nằm trong trang Employers). Các mục nâng cao
// (Payments, Packages, Banners, Settings) sẽ bổ sung ở giai đoạn sau MVP.
export default function Layout({ children }: { children: ReactNode }) {
  const router = useRouter();

  useEffect(() => {
    if (router.pathname !== '/login' && !isLoggedIn()) {
      router.replace('/login');
    }
  }, [router]);

  return (
    <div style={{ display: 'flex', minHeight: '100vh', fontFamily: 'system-ui, sans-serif' }}>
      <aside style={{ width: 220, background: '#0f172a', color: '#fff', padding: 16 }}>
        <h2 style={{ fontSize: 18, marginBottom: 24 }}>VIỆC NHA TRANG</h2>
        <nav style={{ display: 'flex', flexDirection: 'column', gap: 4 }}>
          {NAV_ITEMS.map((item) => (
            <Link
              key={item.href}
              href={item.href}
              style={{
                color: router.pathname === item.href ? '#fff' : '#94a3b8',
                background: router.pathname === item.href ? '#1e293b' : 'transparent',
                padding: '8px 12px',
                borderRadius: 6,
                textDecoration: 'none',
              }}
            >
              {item.label}
            </Link>
          ))}
        </nav>
        <button
          onClick={() => {
            clearToken();
            router.replace('/login');
          }}
          style={{ marginTop: 32, color: '#f87171', background: 'none', border: 'none', cursor: 'pointer' }}
        >
          Đăng xuất
        </button>
      </aside>
      <main style={{ flex: 1, padding: 32, background: '#f8fafc' }}>{children}</main>
    </div>
  );
}
