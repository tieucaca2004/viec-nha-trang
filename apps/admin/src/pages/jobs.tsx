import { useEffect, useState } from 'react';
import { api } from '../lib/api';

interface AdminJob {
  id: string;
  title: string;
  status: string;
  salaryMin: number;
  salaryMax: number;
  employer: { businessName: string };
  area: { name: string };
}

const STATUSES = ['ACTIVE', 'PAUSED', 'CLOSED', 'EXPIRED', 'REJECTED'];

// Duyệt/khóa tin (mục 29): admin đổi trạng thái hoặc gỡ tin vi phạm.
export default function JobsPage() {
  const [jobs, setJobs] = useState<AdminJob[]>([]);

  const load = () => api.get('/admin/jobs').then(setJobs).catch(() => {});

  useEffect(() => {
    load();
  }, []);

  const setStatus = async (id: string, status: string) => {
    await api.patch(`/admin/jobs/${id}/status`, { status });
    load();
  };

  const remove = async (id: string) => {
    if (!window.confirm('Gỡ tin này khỏi hệ thống?')) return;
    await api.post(`/admin/jobs/${id}/remove`);
    load();
  };

  return (
    <div>
      <h1 style={{ fontSize: 24, marginBottom: 16 }}>Jobs</h1>
      <table style={tableStyle}>
        <thead>
          <tr>
            <th style={thStyle}>Tiêu đề</th>
            <th style={thStyle}>Nhà tuyển dụng</th>
            <th style={thStyle}>Khu vực</th>
            <th style={thStyle}>Lương</th>
            <th style={thStyle}>Trạng thái</th>
            <th style={thStyle}></th>
          </tr>
        </thead>
        <tbody>
          {jobs.map((j) => (
            <tr key={j.id}>
              <td style={tdStyle}>{j.title}</td>
              <td style={tdStyle}>{j.employer?.businessName}</td>
              <td style={tdStyle}>{j.area?.name}</td>
              <td style={tdStyle}>{j.salaryMin}–{j.salaryMax}đ</td>
              <td style={tdStyle}>
                <select defaultValue={j.status} onChange={(e) => setStatus(j.id, e.target.value)}>
                  {STATUSES.map((s) => (
                    <option key={s} value={s}>
                      {s}
                    </option>
                  ))}
                </select>
              </td>
              <td style={tdStyle}>
                <button onClick={() => remove(j.id)}>Gỡ tin</button>
              </td>
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
