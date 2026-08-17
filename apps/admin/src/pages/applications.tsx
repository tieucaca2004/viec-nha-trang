import { useEffect, useState } from 'react';
import { api } from '../lib/api';

interface AdminApplication {
  id: string;
  status: string;
  matchScore: number | null;
  job: { title: string };
  jobSeeker: { fullName: string };
}

export default function ApplicationsPage() {
  const [applications, setApplications] = useState<AdminApplication[]>([]);

  useEffect(() => {
    api.get('/admin/applications').then(setApplications).catch(() => {});
  }, []);

  return (
    <div>
      <h1 style={{ fontSize: 24, marginBottom: 16 }}>Applications</h1>
      <table style={tableStyle}>
        <thead>
          <tr>
            <th style={thStyle}>Việc làm</th>
            <th style={thStyle}>Ứng viên</th>
            <th style={thStyle}>Phù hợp</th>
            <th style={thStyle}>Trạng thái</th>
          </tr>
        </thead>
        <tbody>
          {applications.map((a) => (
            <tr key={a.id}>
              <td style={tdStyle}>{a.job?.title}</td>
              <td style={tdStyle}>{a.jobSeeker?.fullName}</td>
              <td style={tdStyle}>{a.matchScore != null ? `${a.matchScore}%` : '—'}</td>
              <td style={tdStyle}>{a.status}</td>
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}

const tableStyle = { width: '100%', borderCollapse: 'collapse' as const, background: '#fff' };
const thStyle = { textAlign: 'left' as const, padding: 10, borderBottom: '1px solid #e2e8f0', fontSize: 13, color: '#64748b' };
const tdStyle = { padding: 10, borderBottom: '1px solid #f1f5f9', fontSize: 14 };
