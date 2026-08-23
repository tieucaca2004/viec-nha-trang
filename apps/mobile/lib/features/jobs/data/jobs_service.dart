import '../../../core/network/api_client.dart';
import '../../../shared/models/job.dart';

/// Bộ lọc tìm việc - đặc tả §10. Khớp query params thật của `GET /jobs` (docs/API.md).
class JobFilters {
  String? keyword;
  String? categoryId;
  String? areaId;
  double? latitude;
  double? longitude;
  double? radiusKm;
  String? employmentType;
  String? shift;
  bool? isUrgent;
  String? sortBy;
  String? startUrgency;
  int? salaryMin;
  int? salaryMax;

  Map<String, dynamic> toQuery() => {
        'keyword': keyword,
        'categoryId': categoryId,
        'areaId': areaId,
        'latitude': latitude,
        'longitude': longitude,
        'radiusKm': radiusKm,
        'employmentType': employmentType,
        'shift': shift,
        'isUrgent': isUrgent,
        'sortBy': sortBy,
        'startUrgency': startUrgency,
        'salaryMin': salaryMin,
        'salaryMax': salaryMax,
      };

  JobFilters copy() => JobFilters()
    ..keyword = keyword
    ..categoryId = categoryId
    ..areaId = areaId
    ..latitude = latitude
    ..longitude = longitude
    ..radiusKm = radiusKm
    ..employmentType = employmentType
    ..shift = shift
    ..isUrgent = isUrgent
    ..sortBy = sortBy
    ..startUrgency = startUrgency
    ..salaryMin = salaryMin
    ..salaryMax = salaryMax;
}

/// Kết quả tìm kiếm có phân trang (đặc tả §9: không tải toàn bộ jobs, dùng pagination).
class JobSearchResult {
  final List<Job> jobs;
  final int total;
  final int limit;
  final int offset;

  JobSearchResult({required this.jobs, required this.total, required this.limit, required this.offset});

  bool get hasMore => offset + jobs.length < total;
}

class JobsService {
  final ApiClient api;
  JobsService(this.api);

  Future<JobSearchResult> search(JobFilters filters, {int limit = 20, int offset = 0}) async {
    final query = filters.toQuery()..addAll({'limit': limit, 'offset': offset});
    final res = await api.get('/jobs', query: query);
    final data = (res['data'] as List).map((e) => Job.fromJson(e)).toList();
    final meta = res['meta'] as Map<String, dynamic>?;
    return JobSearchResult(
      jobs: data,
      total: meta?['total'] ?? data.length,
      limit: meta?['limit'] ?? limit,
      offset: meta?['offset'] ?? offset,
    );
  }

  Future<Map<String, dynamic>> getById(String id) async {
    return await api.get('/jobs/$id') as Map<String, dynamic>;
  }

  // Cache trong bộ nhớ (KHÔNG hard-code data - vẫn lấy từ backend, chỉ lấy 1 lần/phiên app thay vì
  // gọi lại mỗi lần mở màn hình profile/form - đặc tả hotfix §5: "không tải toàn bộ dữ liệu Area
  // nhiều lần", "KHÔNG hard-code lại danh sách Area nếu backend là source of truth". Area/City/
  // Category gần như tĩnh trong 1 phiên sử dụng, không cần refetch mỗi lần build lại 1 form.
  //
  // QUAN TRỌNG (fix lỗi "Chưa có dữ liệu khu vực." dù backend đã có data): CHỈ cache kết quả
  // KHÔNG RỖNG. JobsService sống suốt phiên app (session-lifetime singleton qua ProxyProvider) -
  // nếu 1 lần gọi API trả về [] (timing race lúc backend/DB chưa sẵn sàng, lỗi mạng thoáng qua,
  // ...) mà cache lại [] đó, thì MỌI màn hình sau (kể cả nút THỬ LẠI) sẽ nhận [] mãi mãi trong
  // suốt phiên, không bao giờ tự phục hồi dù backend đã có data thật. Không cache kết quả rỗng ->
  // lần gọi tiếp theo luôn hỏi lại backend cho tới khi có ít nhất 1 phần tử.
  List<JobCategory>? _categoriesCache;
  final Map<String, List<Area>> _areasCache = {}; // key = cityId ?? '' (rỗng = tất cả)
  List<Map<String, dynamic>>? _citiesCache;

  Future<List<JobCategory>> categories({bool forceRefresh = false}) async {
    if (!forceRefresh && _categoriesCache != null) return _categoriesCache!;
    final res = await api.get('/categories') as List;
    final result = res.map((e) => JobCategory.fromJson(e)).toList();
    if (result.isNotEmpty) _categoriesCache = result;
    return result;
  }

  Future<List<Area>> areas({String? cityId, bool forceRefresh = false}) async {
    final key = cityId ?? '';
    final cached = _areasCache[key];
    if (!forceRefresh && cached != null) return cached;
    final res = await api.get('/areas', query: {'cityId': cityId}) as List;
    final result = res.map((e) => Area.fromJson(e)).toList();
    if (result.isNotEmpty) _areasCache[key] = result;
    return result;
  }

  /// V1 chỉ có 1 thành phố (Nha Trang), nhưng API vẫn trả về danh sách để sẵn sàng đa thành phố
  /// (đặc tả §36: không hard-code Nha Trang vào business logic).
  Future<List<Map<String, dynamic>>> cities({bool forceRefresh = false}) async {
    if (!forceRefresh && _citiesCache != null) return _citiesCache!;
    final res = await api.get('/cities') as List;
    final result = res.cast<Map<String, dynamic>>();
    if (result.isNotEmpty) _citiesCache = result;
    return result;
  }
}
