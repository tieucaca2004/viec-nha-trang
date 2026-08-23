import 'dart:async';
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

/// Phân loại lỗi geocoding (đặc tả TINH CHỈNH GEOCODING mục 1) - để caller hiển thị đúng thông
/// báo theo bản chất lỗi thay vì 1 câu chung chung cho mọi trường hợp.
enum GeocodingErrorKind {
  /// Request vượt quá thời gian chờ ([GeocodingService._timeout]).
  timeout,

  /// Lỗi kết nối mạng (không có Internet, DNS lỗi, ...) - không phải timeout, không có response.
  network,

  /// Server trả về HTTP status khác 200.
  httpError,

  /// Request thành công nhưng không có địa điểm/địa chỉ phù hợp.
  noResult,
}

class GeocodingException implements Exception {
  final GeocodingErrorKind kind;
  final String userMessage;
  // Chi tiết kỹ thuật (exception gốc/HTTP status) - CHỈ để debug/log, không hiển thị cho người
  // dùng (userMessage mới là thông báo hiển thị UI).
  final String? debugDetail;
  GeocodingException(this.kind, this.userMessage, {this.debugDetail});

  @override
  String toString() => 'GeocodingException(kind: $kind, userMessage: $userMessage, debugDetail: $debugDetail)';
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
  static const _timeout = Duration(seconds: 10);

  Future<http.Response> _get(Uri uri) async {
    try {
      return await _client.get(uri, headers: {'User-Agent': _userAgent}).timeout(_timeout);
    } on TimeoutException catch (e) {
      throw GeocodingException(GeocodingErrorKind.timeout, 'Hết thời gian chờ. Vui lòng thử lại.', debugDetail: e.toString());
    } catch (e) {
      throw GeocodingException(GeocodingErrorKind.network, 'Không thể kết nối mạng. Vui lòng kiểm tra kết nối.', debugDetail: e.toString());
    }
  }

  void _checkStatus(http.Response response) {
    if (response.statusCode != 200) {
      throw GeocodingException(
        GeocodingErrorKind.httpError,
        'Dịch vụ tìm địa điểm đang gặp lỗi. Vui lòng thử lại.',
        debugDetail: 'HTTP ${response.statusCode}',
      );
    }
  }

  /// Tìm địa điểm theo địa chỉ người dùng nhập (kích hoạt bằng nút TÌM ĐỊA ĐIỂM, KHÔNG tự search
  /// khi đang gõ - đặc tả TINH CHỈNH GEOCODING: giữ nguyên UX, không cần debounce vì không có
  /// request nào phát sinh theo từng ký tự). Ném [GeocodingException] kind=noResult nếu Nominatim
  /// trả về danh sách rỗng, thay vì trả list rỗng cho caller tự suy luận - thống nhất 1 nơi xử lý
  /// lỗi (try/catch theo [GeocodingErrorKind]) cho mọi trường hợp thất bại.
  Future<List<GeocodingResult>> searchAddress(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return [];
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', {
      'q': trimmed,
      'format': 'jsonv2',
      'addressdetails': '1',
      'limit': '5',
      'countrycodes': 'vn',
    });
    final response = await _get(uri);
    _checkStatus(response);
    final list = jsonDecode(response.body) as List;
    final results = list.map((e) => GeocodingResult.fromJson(e as Map<String, dynamic>)).toList();
    if (results.isEmpty) {
      throw GeocodingException(GeocodingErrorKind.noResult, 'Không tìm thấy địa điểm phù hợp. Hãy kiểm tra lại địa chỉ.');
    }
    return results;
  }

  /// Xác định địa chỉ từ toạ độ GPS (reverse geocode). Ném [GeocodingException] kind=noResult nếu
  /// Nominatim không xác định được địa chỉ cho toạ độ này - toạ độ GPS bản thân nó vẫn hợp lệ,
  /// caller (màn hình) phải tự giữ lại toạ độ đã lấy được kể cả khi bước reverse geocode này lỗi
  /// (đặc tả mục 5 gốc), không phải trách nhiệm của service này.
  Future<GeocodingResult> reverseGeocode(double latitude, double longitude) async {
    final uri = Uri.https('nominatim.openstreetmap.org', '/reverse', {
      'lat': latitude.toString(),
      'lon': longitude.toString(),
      'format': 'jsonv2',
      'addressdetails': '1',
    });
    final response = await _get(uri);
    _checkStatus(response);
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    if (map['error'] != null) {
      throw GeocodingException(GeocodingErrorKind.noResult, 'Không tìm thấy địa điểm phù hợp. Hãy kiểm tra lại địa chỉ.');
    }
    return GeocodingResult.fromJson(map);
  }
}
