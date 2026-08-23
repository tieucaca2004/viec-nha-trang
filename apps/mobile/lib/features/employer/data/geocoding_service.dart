import 'dart:convert';
import 'package:http/http.dart' as http;
import '../../../shared/models/job.dart';
import '../../../shared/utils/normalize_vi.dart';

// Các field địa chỉ Nominatim có thể trả về tên phường/xã/địa danh - thử theo thứ tự cụ thể
// nhất trước (suburb/quarter thường là cấp phường/xã ở VN, city/town là cấp rộng hơn).
const _areaAddressCandidateKeys = ['suburb', 'quarter', 'neighbourhood', 'city_district', 'town', 'village'];

/// Map địa chỉ Nominatim trả về sang đúng 1 Area đã có sẵn trong DB (không tạo/bịa Area mới -
/// đặc tả mục 3). Trả null nếu không tìm được khớp nào - caller phải cho chọn thủ công (mục 4),
/// KHÔNG được tự chọn đại 1 Area.
Area? matchAreaFromAddress(Map<String, dynamic> addressComponents, List<Area> areas) {
  for (final key in _areaAddressCandidateKeys) {
    final value = addressComponents[key] as String?;
    if (value == null || value.trim().isEmpty) continue;
    final normalizedValue = normalizeVietnamese(value);
    for (final area in areas) {
      if (normalizeVietnamese(area.name) == normalizedValue) return area;
    }
  }
  // Khớp lỏng hơn (chứa nhau) nếu không có khớp chính xác - vd Nominatim trả "Phường Vĩnh Hải"
  // trong khi Area lưu "Vĩnh Hải".
  for (final key in _areaAddressCandidateKeys) {
    final value = addressComponents[key] as String?;
    if (value == null || value.trim().isEmpty) continue;
    final normalizedValue = normalizeVietnamese(value);
    for (final area in areas) {
      final normalizedAreaName = normalizeVietnamese(area.name);
      if (normalizedValue.contains(normalizedAreaName) || normalizedAreaName.contains(normalizedValue)) return area;
    }
  }
  return null;
}

/// Tìm địa chỉ / xác định vị trí GPS thành địa chỉ đọc được, dùng OpenStreetMap Nominatim -
/// KHÔNG cần API key/billing (đặc tả FIX LỖI "VUI LÒNG NHẬP TÊN..." mục 2/3/5: dự án chưa có
/// Google Maps/Places API key nào, người dùng đã chọn dùng Nominatim thay vì trả tiền Google).
/// Independent với ApiClient (không cần auth, không phải backend của chính ứng dụng).
class GeocodingException implements Exception {
  final String userMessage;
  GeocodingException(this.userMessage);
}

class GeocodingResult {
  final String displayName;
  final double latitude;
  final double longitude;
  // Các field địa chỉ chi tiết Nominatim trả về (suburb/quarter/city_district/...) - dùng để
  // đối chiếu với Area cũ đã có trong DB (đặc tả mục 3: KHÔNG bịa Area mới, chỉ map về Area
  // hiện có bằng tên).
  final Map<String, dynamic> addressComponents;

  GeocodingResult({required this.displayName, required this.latitude, required this.longitude, required this.addressComponents});

  factory GeocodingResult.fromJson(Map<String, dynamic> json) {
    return GeocodingResult(
      displayName: json['display_name'] as String? ?? '',
      latitude: double.parse(json['lat'] as String),
      longitude: double.parse(json['lon'] as String),
      addressComponents: (json['address'] as Map<String, dynamic>?) ?? const {},
    );
  }
}

class GeocodingService {
  final http.Client _client;
  GeocodingService({http.Client? client}) : _client = client ?? http.Client();

  static const _userAgent = 'ViecNhaTrangApp/1.0 (contact: support@viecnhatrang.vn)';

  Future<List<GeocodingResult>> search(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': trimmed,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '5',
      'countrycodes': 'vn',
    });
    http.Response response;
    try {
      response = await _client.get(uri, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw GeocodingException('Không tìm được địa điểm (lỗi mạng). Vui lòng thử lại.');
    }
    if (response.statusCode != 200) {
      throw GeocodingException('Không tìm được địa điểm. Vui lòng thử lại.');
    }
    final list = jsonDecode(response.body) as List;
    return list.map((e) => GeocodingResult.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// Trả null nếu Nominatim không xác định được địa chỉ cho toạ độ này (không phải lỗi mạng -
  /// GPS vẫn hợp lệ, chỉ là không có địa chỉ khớp) - phân biệt với [GeocodingException] (lỗi
  /// mạng/server) để caller xử lý đúng theo mục 5: GPS lỗi mạng vẫn giữ được toạ độ.
  Future<GeocodingResult?> reverse(double latitude, double longitude) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'format': 'jsonv2',
      'addressdetails': '1',
    });
    http.Response response;
    try {
      response = await _client.get(uri, headers: {'User-Agent': _userAgent}).timeout(const Duration(seconds: 10));
    } catch (_) {
      throw GeocodingException('Không xác định được địa chỉ từ vị trí GPS (lỗi mạng).');
    }
    if (response.statusCode != 200) {
      throw GeocodingException('Không xác định được địa chỉ từ vị trí GPS.');
    }
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    if (map['error'] != null) return null;
    return GeocodingResult.fromJson(map);
  }
}
