import { useEffect, useState } from 'react';
import { api } from '../lib/api';

interface Category {
  id: string;
  name: string;
  slug: string;
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

// Quản lý danh mục ngành nghề (mục 29) - admin có thể thêm ngành nghề mới ngoài danh sách gốc.
export default function CategoriesPage() {
  const [categories, setCategories] = useState<Category[]>([]);
  const [name, setName] = useState('');

  const load = () => api.get('/admin/categories').then(setCategories).catch(() => {});

  useEffect(() => {
    load();
  }, []);

  const create = async () => {
    if (!name.trim()) return;
    await api.post('/admin/categories', { name: name.trim(), slug: slugify(name) });
    setName('');
    load();
  };

  const toggleActive = async (c: Category) => {
    await api.patch(`/admin/categories/${c.id}`, { isActive: !c.isActive });
    load();
  };

  return (
    <div>
      <h1 style={{ fontSize: 24, marginBottom: 16 }}>Categories</h1>
      <div style={{ display: 'flex', gap: 8, marginBottom: 16 }}>
        <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Tên ngành nghề mới" style={{ padding: 8, border: '1px solid #cbd5e1', borderRadius: 6 }} />
        <button onClick={create}>Thêm</button>
      </div>
      <table style={tableStyle}>
        <thead>
          <tr>
            <th style={thStyle}>Tên</th>
            <th style={thStyle}>Slug</th>
            <th style={thStyle}>Trạng thái</th>
            <th style={thStyle}></th>
          </tr>
        </thead>
        <tbody>
          {categories.map((c) => (
            <tr key={c.id}>
              <td style={tdStyle}>{c.name}</td>
              <td style={tdStyle}>{c.slug}</td>
              <td style={tdStyle}>{c.isActive ? 'Hoạt động' : 'Ẩn'}</td>
              <td style={tdStyle}>
                <button onClick={() => toggleActive(c)}>{c.isActive ? 'Ẩn' : 'Bật lại'}</button>
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
