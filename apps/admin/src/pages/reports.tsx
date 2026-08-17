import { useEffect, useState } from 'react';
import { api } from '../lib/api';

interface AdminReport {
  id: string;
  targetType: string;
  reason: string;
  status: string;
  note: string | null;
}

const STATUSES = ['OPEN', 'IN_REVIEW', 'RESOLVED', 'DISMISSED'];

// Xử lý báo cáo tin giả/lừa đảo/spam (mục 22).
export default function ReportsPage() {
  const [reports, setReports] = useState<AdminReport[]>([]);

  const load = () => api.get('/admin/reports').then(setReports).catch(() => {});

  useEffect(() => {
    load();
  }, []);

  const resolve = async (id: string, status: string) => {
    const resolvedNote = window.prompt('Ghi chú xử lý (tuỳ chọn)?') ?? undefined;
    await api.patch(`/admin/reports/${id}/resolve`, { status, resolvedNote });
    load();
  };

  return (
    <div>
      <h1 style={{ fontSize: 24, marginBottom: 16 }}>Reports</h1>
      <table style={tableStyle}>
        <thead>
          <tr>
            <th style={thStyle}>Loại</th>
            <th style={thStyle}>Lý do</th>
            <th style={thStyle}>Ghi chú</th>
            <th style={thStyle}>Trạng thái</th>
            <th style={thStyle}></th>
          </tr>
        </thead>
        <tbody>
          {reports.map((r) => (
            <tr key={r.id}>
              <td style={tdStyle}>{r.targetType}</td>
              <td style={tdStyle}>{r.reason}</td>
              <td style={tdStyle}>{r.note}</td>
              <td style={tdStyle}>{r.status}</td>
              <td style={tdStyle}>
                <select defaultValue="" onChange={(e) => e.target.value && resolve(r.id, e.target.value)}>
                  <option value="" disabled>
                    Xử lý...
                  </option>
                  {STATUSES.map((s) => (
                    <option key={s} value={s}>
                      {s}
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
