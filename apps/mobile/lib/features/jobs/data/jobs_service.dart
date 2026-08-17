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
    ..startUrgency = startUrgency;
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

  Future<List<JobCategory>> categories() async {
    final res = await api.get('/categories') as List;
    return res.map((e) => JobCategory.fromJson(e)).toList();
  }

  Future<List<Area>> areas({String? cityId}) async {
    final res = await api.get('/areas', query: {'cityId': cityId}) as List;
    return res.map((e) => Area.fromJson(e)).toList();
  }

  /// V1 chỉ có 1 thành phố (Nha Trang), nhưng API vẫn trả về danh sách để sẵn sàng đa thành phố
  /// (đặc tả §36: không hard-code Nha Trang vào business logic).
  Future<List<Map<String, dynamic>>> cities() async {
    final res = await api.get('/cities') as List;
    return res.cast<Map<String, dynamic>>();
  }
}
