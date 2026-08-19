// Salary benchmark cho Nha Trang/Khánh Hòa - dùng để hiệu chỉnh SALARY_TIER_MONTH trong
// seed-synthetic.ts (đặc tả "Nguồn thật → thu thập → dedupe → phân loại → benchmark →
// cập nhật generator → regenerate synthetic jobs").
//
// PHƯƠNG PHÁP & GIỚI HẠN TRUNG THỰC (đọc trước khi dùng số liệu này):
// - Môi trường thực thi này CHẶN WebFetch tới mọi domain tuyển dụng thật (careerviet.vn,
//   topcv.vn, vieclamtot.com, thongtinvieclamkhanhhoa.vn, vieclamkhanhhoa.com, vnexpress.net,
//   hoteljob.vn... đều trả lỗi EGRESS_BLOCKED khi thử mở trực tiếp từng tin). KHÔNG thể mở
//   từng trang tin để trích xuất observation-level (sourceUrl/ngày đăng chính xác/mã tin) như
//   schema đầy đủ yêu cầu.
// - Số liệu dưới đây lấy từ WebSearch (search snippet do AI tóm tắt kết quả tìm kiếm thật, có
//   trích dẫn tên nguồn) - KHÔNG phải trích xuất trực tiếp từ HTML gốc từng tin. Vì vậy:
//   * KHÔNG có sourceUrl xác thực cho từng observation (chỉ có tên site/domain nguồn).
//   * KHÔNG dedupe ở mức "từng tin cụ thể" được (không có ID tin) - chỉ dedupe ở mức
//     "1 cụm kết quả tìm kiếm cho 1 vị trí" (không đếm lặp cùng 1 cụm search làm 2 observation).
//   * confidence tối đa là MEDIUM (không phải HIGH) vì không tự kiểm chứng lại trang gốc được.
// - Ưu tiên dữ liệu Nha Trang/Khánh Hòa; nơi search không trả kết quả riêng cho Khánh Hòa (đã
//   nêu rõ trong snippet), đánh dấu geography: 'VN' và confidence: 'LOW'.
// - Đây là 24 cụm quan sát tổng hợp (không phải 24 tin riêng lẻ) - KHÔNG đủ để tính median/p25/p75
//   thống kê nghiêm ngặt; dùng làm CĂN CỨ HIỆU CHỈNH range hợp lý cho generator, không phải
//   benchmark chính xác cấp sản xuất.

export type SalaryUnit = 'HOUR' | 'DAY' | 'MONTH' | 'SHIFT';
export type Confidence = 'HIGH' | 'MEDIUM' | 'LOW';
export type Geography = 'NHA_TRANG' | 'KHANH_HOA' | 'VN';

export interface SalaryObservation {
  sourceName: string; // tên site nguồn (không có URL tin cụ thể - xem giới hạn ở trên)
  sourceType: 'WEBSITE';
  position: string;
  category: string; // khớp 1 trong 26 ngành của Phần 2
  businessType?: string; // vd "cafe bình dân", "hotel 5 sao" - chỉ điền khi search cho biết rõ
  location: Geography;
  salaryType: SalaryUnit;
  salaryMin: number;
  salaryMax: number;
  confidence: Confidence;
  note: string; // trích dẫn ngắn từ search snippet + searchQuery dùng để tìm ra nó
}

export const SALARY_OBSERVATIONS: SalaryObservation[] = [
  {
    sourceName: 'thongtinvieclamkhanhhoa.vn',
    sourceType: 'WEBSITE',
    position: 'Tài xế B2',
    category: 'Tài xế',
    location: 'NHA_TRANG',
    salaryType: 'MONTH',
    salaryMin: 7_500_000,
    salaryMax: 8_000_000,
    confidence: 'MEDIUM',
    note: 'Cty TNHH TM Dũng Tuyên, nam 30-40 tuổi, bằng B2, >5 năm kinh nghiệm. query: "thongtinvieclamkhanhhoa.vn tuyển dụng lương Nha Trang"',
  },
  {
    sourceName: 'careerviet.vn',
    sourceType: 'WEBSITE',
    position: 'Kỹ thuật/kỹ sư (chung)',
    category: 'Kỹ thuật',
    location: 'KHANH_HOA',
    salaryType: 'MONTH',
    salaryMin: 10_000_000,
    salaryMax: 20_000_000,
    confidence: 'MEDIUM',
    note: 'query: "careerviet.vn tuyển dụng Nha Trang Khánh Hòa lương"',
  },
  {
    sourceName: 'careerviet.vn',
    sourceType: 'WEBSITE',
    position: 'Tài xế (theo loại xe/ca)',
    category: 'Tài xế',
    location: 'KHANH_HOA',
    salaryType: 'MONTH',
    salaryMin: 8_000_000,
    salaryMax: 15_000_000,
    confidence: 'MEDIUM',
    note: 'query: "careerviet.vn tuyển dụng Nha Trang Khánh Hòa lương"',
  },
  {
    sourceName: 'careerviet.vn',
    sourceType: 'WEBSITE',
    position: 'Xây dựng (chung)',
    category: 'Xây dựng',
    location: 'KHANH_HOA',
    salaryType: 'MONTH',
    salaryMin: 7_000_000,
    salaryMax: 15_000_000,
    confidence: 'MEDIUM',
    note: 'query: "careerviet.vn tuyển dụng Nha Trang Khánh Hòa lương"',
  },
  {
    sourceName: 'vieclamtot.com',
    sourceType: 'WEBSITE',
    position: 'Bảo vệ (ca giờ)',
    category: 'Bảo vệ',
    location: 'NHA_TRANG',
    salaryType: 'HOUR',
    salaryMin: 19_000,
    salaryMax: 22_000,
    confidence: 'MEDIUM',
    note: 'Bảo vệ Lotte Mart Nha Trang, ca 4h/6h/8h/12h. query: "vieclamtot.com Nha Trang lương giờ"',
  },
  {
    sourceName: 'muaban.net / careerviet.vn (cụm cafe)',
    sourceType: 'WEBSITE',
    position: 'Phục vụ/pha chế quán cafe (part-time)',
    category: 'F&B',
    businessType: 'cafe bình dân/phổ thông',
    location: 'VN',
    salaryType: 'HOUR',
    salaryMin: 14_000,
    salaryMax: 27_000,
    confidence: 'LOW',
    note: 'Snippet không xác nhận riêng Nha Trang, chỉ VN nói chung: "14.000-21.000đ/h part-time, 17.000-27.000đ/h". query: "tuyển phục vụ cafe Nha Trang lương giờ nghìn/giờ"',
  },
  {
    sourceName: 'careerviet.vn / tuyendungnhatrang.com',
    sourceType: 'WEBSITE',
    position: 'Nhân viên nhà hàng (thoả thuận)',
    category: 'Nhà hàng',
    businessType: 'quán ăn phổ thông',
    location: 'NHA_TRANG',
    salaryType: 'MONTH',
    salaryMin: 2_500_000,
    salaryMax: 5_000_000,
    confidence: 'LOW',
    note: 'Mức "thoả thuận" thấp bất thường - có thể chỉ là phụ cấp cơ bản + tip, không phải tổng thu nhập. query: "tuyển nhân viên nhà hàng resort Nha Trang lương tháng triệu"',
  },
  {
    sourceName: 'tuyendungnhatrang.com',
    sourceType: 'WEBSITE',
    position: 'Lễ tân khách sạn 3 sao',
    category: 'Khách sạn',
    businessType: 'hotel 3 sao',
    location: 'NHA_TRANG',
    salaryType: 'MONTH',
    salaryMin: 3_000_000,
    salaryMax: 5_000_000,
    confidence: 'MEDIUM',
    note: 'Lương cứng, cộng tip/thưởng tổng 7-10tr. query: "tuyển lễ tân khách sạn Nha Trang lương"',
  },
  {
    sourceName: 'tuyendungnhatrang.com',
    sourceType: 'WEBSITE',
    position: 'Lễ tân khách sạn 4 sao',
    category: 'Khách sạn',
    businessType: 'hotel 4 sao',
    location: 'NHA_TRANG',
    salaryType: 'MONTH',
    salaryMin: 4_000_000,
    salaryMax: 6_000_000,
    confidence: 'MEDIUM',
    note: 'query: "tuyển lễ tân khách sạn Nha Trang lương"',
  },
  {
    sourceName: 'tuyendungnhatrang.com',
    sourceType: 'WEBSITE',
    position: 'Lễ tân khách sạn 5 sao',
    category: 'Khách sạn',
    businessType: 'hotel/resort 5 sao',
    location: 'NHA_TRANG',
    salaryType: 'MONTH',
    salaryMin: 5_000_000,
    salaryMax: 7_000_000,
    confidence: 'MEDIUM',
    note: 'Cứng 5-7tr, tổng thu nhập kèm tip 7-10tr. query: "tuyển lễ tân khách sạn Nha Trang lương"',
  },
  {
    sourceName: 'joboko.com',
    sourceType: 'WEBSITE',
    position: 'Kinh doanh/Sales BĐS',
    category: 'Sales',
    location: 'NHA_TRANG',
    salaryType: 'MONTH',
    salaryMin: 6_000_000,
    salaryMax: 12_000_000,
    confidence: 'MEDIUM',
    note: 'Cứng 6tr+ hoa hồng, ước tổng theo Sales FMCG tương tự 12-15tr. query: "tuyển nhân viên kinh doanh sales Nha Trang lương cứng hoa hồng"',
  },
  {
    sourceName: 'topcv.vn / 123job.vn',
    sourceType: 'WEBSITE',
    position: 'Kế toán',
    category: 'Kế toán',
    location: 'NHA_TRANG',
    salaryType: 'MONTH',
    salaryMin: 7_000_000,
    salaryMax: 15_000_000,
    confidence: 'MEDIUM',
    note: 'TAZA GROUP niêm yết 10-15tr; phổ biến toàn khu vực 7-15tr (dải rộng 6-20tr). query: "tuyển kế toán Nha Trang Khánh Hòa lương triệu"',
  },
  {
    sourceName: 'muaban.net / 123job.vn',
    sourceType: 'WEBSITE',
    position: 'Bảo vệ ca đêm (tháng)',
    category: 'Bảo vệ',
    location: 'NHA_TRANG',
    salaryType: 'MONTH',
    salaryMin: 4_500_000,
    salaryMax: 9_000_000,
    confidence: 'MEDIUM',
    note: 'query: "tuyển bảo vệ Nha Trang lương tháng triệu ca đêm"',
  },
  {
    sourceName: 'vieclamtot.com',
    sourceType: 'WEBSITE',
    position: 'Nhân viên bán hàng siêu thị',
    category: 'Bán lẻ',
    location: 'NHA_TRANG',
    salaryType: 'MONTH',
    salaryMin: 9_000_000,
    salaryMax: 13_000_000,
    confidence: 'MEDIUM',
    note: 'Coop Nha Trang, 02 Lê Hồng Phong. query: "tuyển nhân viên bán hàng siêu thị Nha Trang lương"',
  },
  {
    sourceName: 'nhatrangjob.vn',
    sourceType: 'WEBSITE',
    position: 'Nhân viên IT lập trình CSDL',
    category: 'IT',
    location: 'NHA_TRANG',
    salaryType: 'MONTH',
    salaryMin: 10_000_000,
    salaryMax: 22_000_000,
    confidence: 'MEDIUM',
    note: 'Cty TNHH Tự động hoá MenT, lương đến 22tr. query: "tuyển IT lập trình viên Nha Trang Khánh Hòa lương"',
  },
  {
    sourceName: 'topcv.vn',
    sourceType: 'WEBSITE',
    position: 'Kỹ thuật viên Spa',
    category: 'Spa',
    location: 'NHA_TRANG',
    salaryType: 'MONTH',
    salaryMin: 4_000_000,
    salaryMax: 30_000_000,
    confidence: 'LOW',
    note: 'TAZA GROUP "thu nhập 30tr+" gồm cứng 4tr + hoa hồng 15% + tip - biên độ rất rộng, không phải lương cứng thuần. query: "tuyển nhân viên spa massage Nha Trang lương"',
  },
  {
    sourceName: 'careerviet.vn / vietnamworks.com',
    sourceType: 'WEBSITE',
    position: 'Nhân viên kho/logistics',
    category: 'Kho vận',
    location: 'VN',
    salaryType: 'MONTH',
    salaryMin: 8_000_000,
    salaryMax: 12_000_000,
    confidence: 'LOW',
    note: 'Snippet không xác nhận riêng Nha Trang. query: "tuyển nhân viên kho logistics Nha Trang lương triệu"',
  },
  {
    sourceName: 'hoteljob.vn / nhatrangjob.vn',
    sourceType: 'WEBSITE',
    position: 'Hướng dẫn viên du lịch',
    category: 'Du lịch',
    location: 'NHA_TRANG',
    salaryType: 'MONTH',
    salaryMin: 7_000_000,
    salaryMax: 10_000_000,
    confidence: 'MEDIUM',
    note: 'Cơ bản + phụ cấp/hoa hồng/tip cộng thêm ngoài mức này. query: "tuyển hướng dẫn viên du lịch Nha Trang lương"',
  },
  {
    sourceName: 'careerviet.vn / vietnamworks.com',
    sourceType: 'WEBSITE',
    position: 'Giáo viên tiếng Anh full-time',
    category: 'Giáo dục',
    location: 'VN',
    salaryType: 'MONTH',
    salaryMin: 25_000_000,
    salaryMax: 40_000_000,
    confidence: 'LOW',
    note: 'Snippet không tách riêng Nha Trang, có thể lệch cao do gộp trung tâm lớn HN/HCM. query: "tuyển giáo viên tiếng Anh Nha Trang lương"',
  },
  {
    sourceName: 'careerviet.vn / vietnamworks.com',
    sourceType: 'WEBSITE',
    position: 'Giáo viên tiếng Anh part-time',
    category: 'Giáo dục',
    location: 'VN',
    salaryType: 'HOUR',
    salaryMin: 25_000,
    salaryMax: 35_000,
    confidence: 'LOW',
    note: 'query: "tuyển giáo viên tiếng Anh Nha Trang lương"',
  },
  {
    sourceName: 'vieclam24h.vn (không có số cho Nha Trang)',
    sourceType: 'WEBSITE',
    position: 'Chăm sóc khách hàng/Tổng đài',
    category: 'Chăm sóc khách hàng',
    location: 'VN',
    salaryType: 'MONTH',
    salaryMin: 8_000_000,
    salaryMax: 15_000_000,
    confidence: 'LOW',
    note: 'Search thừa nhận chỉ có kết quả HN/HCM, không có Nha Trang. query: "tuyển nhân viên chăm sóc khách hàng tổng đài Nha Trang lương"',
  },
];
