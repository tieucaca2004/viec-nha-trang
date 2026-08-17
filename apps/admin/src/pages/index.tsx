import { useEffect, useState } from 'react';
import { api } from '../lib/api';

interface DashboardStats {
  totalUsers: number;
  totalJobSeekers: number;
  totalEmployers: number;
  activeJobs: number;
  newJobsToday: number;
  applications: number;
  reportsOpen: number;
}

// Dashboard tối thiểu theo mục 29: tổng user, job seeker, employer, tin đang tuyển,
// tin mới, ứng tuyển, báo cáo chờ xử lý. Doanh thu sẽ bổ sung khi bật thanh toán.
export default function DashboardPage() {
  const [stats, setStats] = useState<DashboardStats | null>(null);

  useEffect(() => {
    api.get('/admin/dashboard').then(setStats).catch(() => {});
  }, []);

  const cards: { label: string; value: number | undefined }[] = [
    { label: 'Tổng người dùng', value: stats?.totalUsers },
    { label: 'Người tìm việc', value: stats?.totalJobSeekers },
    { label: 'Nhà tuyển dụng', value: stats?.totalEmployers },
    { label: 'Tin đang tuyển', value: stats?.activeJobs },
    { label: 'Tin mới hôm nay', value: stats?.newJobsToday },
    { label: 'Tổng ứng tuyển', value: stats?.applications },
    { label: 'Báo cáo chờ xử lý', value: stats?.reportsOpen },
  ];

  return (
    <div>
      <h1 style={{ fontSize: 24, marginBottom: 24 }}>Dashboard</h1>
      <div style={{ display: 'grid', gridTemplateColumns: 'repeat(auto-fill, minmax(200px, 1fr))', gap: 16 }}>
        {cards.map((c) => (
          <div key={c.label} style={{ background: '#fff', padding: 20, borderRadius: 8, border: '1px solid #e2e8f0' }}>
            <div style={{ fontSize: 13, color: '#64748b' }}>{c.label}</div>
            <div style={{ fontSize: 28, fontWeight: 700 }}>{c.value ?? '—'}</div>
          </div>
        ))}
      </div>
    </div>
  );
}
