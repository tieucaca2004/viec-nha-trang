import { useEffect, useState } from 'react';
import { api } from '../lib/api';

interface City {
  id: string;
  name: string;
}

interface AreaRow {
  id: string;
  name: string;
  isActive: boolean;
}

function slugify(input: string) {
  return input
    .toLowerCase()
    .normalize('NFD')
    .replace(/[̀-ͯ]/g, '')
    .replace(/đ/g, 'd')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/(^-|-$)/g, '');
}

// Quản lý khu vực (mục 9, 31) - admin cập nhật danh sách phường/xã theo thành phố,
// đây cũng là nơi thêm thành phố mới khi mở rộng ngoài Nha Trang sau này.
export default function AreasPage() {
  const [cities, setCities] = useState<City[]>([]);
  const [cityId, setCityId] = useState('');
  const [areas, setAreas] = useState<AreaRow[]>([]);
  const [name, setName] = useState('');

  useEffect(() => {
    api.get('/cities').then((c) => {
      setCities(c);
      if (c[0]) setCityId(c[0].id);
    }).catch(() => {});
  }, []);

  const load = (cid: string) => api.get(`/admin/areas?cityId=${cid}`).then(setAreas).catch(() => {});

  useEffect(() => {
    if (cityId) load(cityId);
  }, [cityId]);

  const create = async () => {
    if (!name.trim() || !cityId) return;
    await api.post('/admin/areas', { cityId, name: name.trim(), slug: slugify(name) });
    setName('');
    load(cityId);
  };

  const toggleActive = async (a: AreaRow) => {
    await api.patch(`/admin/areas/${a.id}`, { isActive: !a.isActive });
    load(cityId);
  };

  return (
    <div>
      <h1 style={{ fontSize: 24, marginBottom: 16 }}>Areas</h1>
      <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
        <select value={cityId} onChange={(e) => setCityId(e.target.value)}>
          {cities.map((c) => (
            <option key={c.id} value={c.id}>
              {c.name}
            </option>
          ))}
        </select>
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Tên khu vực mới" style={{ padding: 8, border: '1px solid #cbd5e1', borderRadius: 6 }} />
        <button onClick={create}>Thêm</button>
      </div>
      <table style={tableStyle}>
        <thead>
          <tr>
            <th style={thStyle}>Tên khu vực</th>
            <th style={thStyle}>Trạng thái</th>
            <th style={thStyle}></th>
          </tr>
        </thead>
        <tbody>
          {areas.map((a) => (
            <tr key={a.id}>
              <td style={tdStyle}>{a.name}</td>
              <td style={tdStyle}>{a.isActive ? 'Hoạt động' : 'Ẩn'}</td>
              <td style={tdStyle}>
                <button onClick={() => toggleActive(a)}>{a.isActive ? 'Ẩn' : 'Bật lại'}</button>
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
