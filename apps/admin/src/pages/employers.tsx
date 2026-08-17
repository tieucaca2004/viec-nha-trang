import { useEffect, useState } from 'react';
import { api } from '../lib/api';

interface AdminEmployer {
  id: string;
  businessName: string;
  verificationLevel: string;
  ratingAvg: number;
  hiredCount: number;
}

const LEVELS = ['UNVERIFIED', 'PHONE_VERIFIED', 'BUSINESS_VERIFIED', 'TRUSTED'];

// Xác minh nhà tuyển dụng (mục 20): admin nâng cấp cấp độ để hiện badge trên app.
export default function EmployersPage() {
  const [employers, setEmployers] = useState<AdminEmployer[]>([]);

  const load = () => api.get('/admin/employers').then(setEmployers).catch(() => {});

  useEffect(() => {
    load();
  }, []);

  const verify = async (id: string, level: string) => {
    await api.post(`/admin/employers/${id}/verify`, { level });
    load();
  };

  return (
    <div>
      <h1 style={{ fontSize: 24, marginBottom: 16 }}>Employers</h1>
      <table style={tableStyle}>
        <thead>
          <tr>
            <th style={thStyle}>Tên doanh nghiệp</th>
            <th style={thStyle}>Xác minh</th>
            <th style={thStyle}>Đánh giá</th>
            <th style={thStyle}>Đã tuyển</th>
            <th style={thStyle}>Cập nhật</th>
          </tr>
        </thead>
        <tbody>
          {employers.map((e) => (
            <tr key={e.id}>
              <td style={tdStyle}>{e.businessName}</td>
              <td style={tdStyle}>{e.verificationLevel}</td>
              <td style={tdStyle}>⭐ {e.ratingAvg.toFixed(1)}</td>
              <td style={tdStyle}>{e.hiredCount}</td>
              <td style={tdStyle}>
                <select defaultValue={e.verificationLevel} onChange={(ev) => verify(e.id, ev.target.value)}>
                  {LEVELS.map((l) => (
                    <option key={l} value={l}>
                      {l}
                    </option>
                  ))}
                </select>
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
