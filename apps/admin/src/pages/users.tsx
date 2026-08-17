import { useEffect, useState } from 'react';
import { api } from '../lib/api';

interface AdminUser {
  id: string;
  phone: string | null;
  roles: string[];
  isBanned: boolean;
  createdAt: string;
}

export default function UsersPage() {
  const [users, setUsers] = useState<AdminUser[]>([]);

  const load = () => api.get('/admin/users').then(setUsers).catch(() => {});

  useEffect(() => {
    load();
  }, []);

  const ban = async (id: string) => {
    const reason = window.prompt('Lý do khóa tài khoản?') ?? '';
    await api.post(`/admin/users/${id}/ban`, { reason });
    load();
  };

  const unban = async (id: string) => {
    await api.post(`/admin/users/${id}/unban`);
    load();
  };

  return (
    <div>
      <h1 style={{ fontSize: 24, marginBottom: 16 }}>Users</h1>
      <table style={tableStyle}>
        <thead>
          <tr>
            <th style={thStyle}>SĐT</th>
            <th style={thStyle}>Vai trò</th>
            <th style={thStyle}>Trạng thái</th>
            <th style={thStyle}>Ngày tạo</th>
            <th style={thStyle}></th>
          </tr>
        </thead>
        <tbody>
          {users.map((u) => (
            <tr key={u.id}>
              <td style={tdStyle}>{u.phone}</td>
              <td style={tdStyle}>{u.roles.join(', ')}</td>
              <td style={tdStyle}>{u.isBanned ? '🔴 Đã khóa' : '🟢 Hoạt động'}</td>
              <td style={tdStyle}>{new Date(u.createdAt).toLocaleDateString('vi-VN')}</td>
              <td style={tdStyle}>
                {u.isBanned ? <button onClick={() => unban(u.id)}>Mở khóa</button> : <button onClick={() => ban(u.id)}>Khóa</button>}
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
