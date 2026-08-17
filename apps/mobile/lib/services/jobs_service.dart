import '../core/api_client.dart';
import '../models/job.dart';

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
      };
}

class JobsService {
  final ApiClient api;
  JobsService(this.api);

  Future<List<Job>> search(JobFilters filters, {int limit = 20, int offset = 0}) async {
    final query = filters.toQuery()..addAll({'limit': limit, 'offset': offset});
    final res = await api.get('/jobs', query: query);
    final data = res['data'] as List;
    return data.map((e) => Job.fromJson(e)).toList();
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

  /// V1 chỉ có 1 thành phố (Nha Trang), nhưng API vẫn trả về danh sách để sẵn sàng đa thành phố (mục 31).
  Future<List<Map<String, dynamic>>> cities() async {
    final res = await api.get('/cities') as List;
    return res.cast<Map<String, dynamic>>();
  }
}
