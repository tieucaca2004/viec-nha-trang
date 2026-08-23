import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/job.dart';
import '../../../shared/utils/normalize_vi.dart';
import '../../jobs/data/jobs_service.dart';
import '../data/employer_profile_service.dart';
import '../data/geocoding_service.dart';
import '../../auth/data/auth_service.dart';
import '../../../shared/widgets/phone_verification_sheet.dart';

/// Tạo hồ sơ doanh nghiệp/cơ sở (đặc tả §18 Phase 3, §13 gốc bước chuẩn bị).
/// SĐT tài khoản (khác SĐT liên hệ của cơ sở bên dưới) hiển thị trạng thái xác minh thật từ /me -
/// từ khi đăng ký chuyển sang dùng email (đặc tả §1 phase kế tiếp), SĐT KHÔNG còn tự động
/// verified nữa, phải xác minh riêng khi cần đăng tuyển (đặc tả §3/§4).
///
/// Sửa lỗi "VUI LÒNG NHẬP TÊN DOANH NGHIỆP VÀ CHỌN KHU VỰC" (FIX LỖI mục 1-6): trước đây employer
/// phải tự nhập latitude/longitude bằng tay và tự chọn Area từ danh sách phẳng - người dùng thật
/// nhập địa chỉ + GPS hợp lệ nhưng Area picker báo "Không tìm thấy khu vực phù hợp." dù họ chưa hề
/// gõ tìm kiếm gì, vì _areas rỗng do GET /areas lỗi/chưa tải xong bị hiển thị NHẦM thành "tìm
/// không ra" thay vì "chưa tải được" (xem _loadAreas()/_areasLoadError bên dưới - đây là root
/// cause thật, không phải đoán). Nhân dịp sửa, triển khai luôn tìm địa chỉ + tự map Area bằng
/// OpenStreetMap Nominatim (KHÔNG cần Google Maps/Places API key - dự án chưa có key nào, người
/// dùng đã chọn Nominatim thay vì trả tiền Google) - xem geocoding_service.dart. latitude/longitude
/// vẫn được lưu/gửi lên backend y hệt trước, chỉ không còn bắt người dùng tự gõ số toạ độ nữa.
class EmployerBusinessSetupScreen extends StatefulWidget {
  const EmployerBusinessSetupScreen({super.key});

  @override
  State<EmployerBusinessSetupScreen> createState() => _EmployerBusinessSetupScreenState();
}

class _EmployerBusinessSetupScreenState extends State<EmployerBusinessSetupScreen> {
  final _businessNameController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _locationNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _phoneController = TextEditingController();
  final _areaSearchController = TextEditingController();
  String _areaSearchQuery = '';

  List<Area> _areas = [];
  // Lỗi cụ thể của RIÊNG lần tải /areas - tách biệt khỏi _error chung (có thể tới từ 1 trong 4
  // request khác) để phân biệt đúng "chưa tải được danh sách khu vực" (root cause bug thật) với
  // "đã tải xong nhưng tìm kiếm không khớp" (2 trạng thái khác nhau, không được gộp chung).
  ApiException? _areasLoadError;
  String? _areaId;
  String? _cityId;
  // true nếu areaId hiện tại đến từ tự động map địa chỉ (không phải người dùng tự bấm chọn) -
  // chỉ dùng để hiển thị đúng thông báo, không ảnh hưởng validation.
  bool _areaAutoMatched = false;

  double? _latitude;
  double? _longitude;
  List<GeocodingResult> _searchResults = [];
  bool _searching = false;
  bool _locatingGps = false;
  String? _geocodingError;

  List<Area> get _filteredAreas {
    if (_areaSearchQuery.trim().isEmpty) return _areas;
    final normalizedQuery = normalizeVietnamese(_areaSearchQuery);
    return _areas.where((a) => normalizeVietnamese(a.name).contains(normalizedQuery)).toList();
  }

  bool _saving = false;
  bool _loadingExisting = true;
  // Backend chưa có API cập nhật cơ sở đã tạo (chỉ có GET/POST /me/employer-profile/locations,
  // không có PATCH/PUT theo id) - nếu đã có cơ sở, khoá phần vị trí để tránh tạo trùng lặp thay
  // vì âm thầm POST thêm 1 bản ghi mới. Xem báo cáo cuối để biết endpoint backend cần bổ sung.
  bool _hasExistingLocation = false;
  Map<String, dynamic>? _me;
  String? _error;

  bool get _hasValidLocation => _latitude != null && _longitude != null;

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  @override
  void dispose() {
    _businessNameController.dispose();
    _descriptionController.dispose();
    _locationNameController.dispose();
    _addressController.dispose();
    _phoneController.dispose();
    _areaSearchController.dispose();
    super.dispose();
  }

  // Hotfix perf: 5 request ĐỘC LẬP (areas/cities/employerProfile/locations/me) trước đây await
  // TUẦN TỰ - trên mạng LAN/WiFi thật, mỗi round-trip cộng dồn (vd 5 x 300ms = 1.5s+ chỉ riêng
  // latency, chưa tính request nào chậm/lỗi làm các request SAU nó không bao giờ chạy) - đây là
  // nguyên nhân thật của "spinner gần như đứng"/"Kết nối quá chậm" trên màn hồ sơ doanh nghiệp.
  // Sửa: chạy song song bằng Future.wait (giảm tổng thời gian chờ xuống bằng request CHẬM NHẤT
  // thay vì TỔNG cả 5 request), và 1 request lỗi không làm mất dữ liệu các request khác đã tải
  // được (đặc tả §2/§7 hotfix).
  Future<void> _loadAreas() async {
    final jobsService = context.read<JobsService>();
    final profileService = context.read<EmployerProfileService>();
    final authService = context.read<AuthService>();
    setState(() {
      _loadingExisting = true;
      _error = null;
    });

    final results = await Future.wait<Object?>([
      _safeCall(jobsService.areas()),
      _safeCall(jobsService.cities()),
      _safeCall(profileService.getEmployerProfile()),
      _safeCall(profileService.myEmployerLocations()),
      _safeCall(authService.getMe()),
    ]);
    if (!mounted) return;

    final areasResult = results[0];
    final citiesResult = results[1];
    final existingProfileResult = results[2];
    final existingLocationsResult = results[3];
    final meResult = results[4];

    // Nếu có request lỗi, báo lỗi (đủ để người dùng bấm THỬ LẠI) - không chặn hiển thị phần dữ
    // liệu đã tải thành công từ các request khác.
    final errors = [areasResult, citiesResult, existingProfileResult, existingLocationsResult, meResult].whereType<ApiException>();
    final firstError = errors.isEmpty ? null : errors.first;

    setState(() {
      if (areasResult is! ApiException) {
        _areas = areasResult as List<Area>;
        _areasLoadError = null;
      } else {
        _areasLoadError = areasResult;
      }
      if (meResult is! ApiException) _me = meResult as Map<String, dynamic>?;
      final cities = citiesResult is! ApiException ? citiesResult as List<Map<String, dynamic>> : const <Map<String, dynamic>>[];
      if (cities.isNotEmpty) _cityId = cities.first['id'] as String;

      final existingProfile = existingProfileResult is! ApiException ? existingProfileResult as Map<String, dynamic>? : null;
      if (existingProfile != null) {
        _businessNameController.text = (existingProfile['businessName'] as String?) ?? '';
        _descriptionController.text = (existingProfile['description'] as String?) ?? '';
      }

      final existingLocations = existingLocationsResult is! ApiException ? existingLocationsResult as List : const [];
      if (existingLocations.isNotEmpty) {
        final loc = existingLocations.first as Map<String, dynamic>;
        _hasExistingLocation = true;
        _locationNameController.text = (loc['name'] as String?) ?? '';
        _addressController.text = (loc['address'] as String?) ?? '';
        _phoneController.text = (loc['phone'] as String?) ?? '';
        _areaId = loc['areaId'] as String?;
        _cityId = (loc['cityId'] as String?) ?? _cityId;
        final lat = loc['latitude'];
        final lng = loc['longitude'];
        if (lat != null) _latitude = (lat as num).toDouble();
        if (lng != null) _longitude = (lng as num).toDouble();
      }

      _error = firstError?.userMessage;
      _loadingExisting = false;
    });
  }

  Future<Object?> _safeCall(Future<Object?> future) async {
    try {
      return await future;
    } on ApiException catch (e) {
      return e;
    }
  }

  /// Áp dụng 1 kết quả tìm địa chỉ (do người dùng bấm chọn hoặc từ GPS reverse-geocode): điền địa
  /// chỉ, lưu toạ độ nội bộ, và thử tự map sang Area đã có sẵn (đặc tả mục 3) - KHÔNG bịa Area
  /// mới, chỉ map về Area hiện có. Không map được thì để người dùng chọn thủ công (mục 4).
  void _applyGeocodingResult(GeocodingResult result) {
    _addressController.text = result.displayName;
    _latitude = result.latitude;
    _longitude = result.longitude;
    final matched = matchAreaFromAddress(result.addressComponents, _areas);
    if (matched != null) {
      _areaId = matched.id;
      _areaAutoMatched = true;
    } else {
      _areaId = null;
      _areaAutoMatched = false;
    }
  }

  Future<void> _searchAddress() async {
    final query = _addressController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _geocodingError = null;
      _searchResults = [];
    });
    try {
      final geocodingService = context.read<GeocodingService>();
      final results = await geocodingService.search(query);
      if (!mounted) return;
      setState(() {
        _searchResults = results;
        if (results.isEmpty) _geocodingError = 'Không tìm thấy địa điểm phù hợp. Bạn có thể chọn khu vực thủ công bên dưới.';
      });
    } on GeocodingException catch (e) {
      if (!mounted) return;
      setState(() => _geocodingError = e.userMessage);
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  void _selectSearchResult(GeocodingResult result) {
    setState(() {
      _applyGeocodingResult(result);
      _searchResults = [];
      _geocodingError = null;
    });
  }

  /// Lấy vị trí GPS hiện tại rồi tự xác định địa chỉ + Area qua reverse-geocode (đặc tả mục 5) -
  /// cùng pattern permission không chặn app như home_screen.dart (§22 gốc: từ chối quyền không
  /// được crash/chặn luồng, chỉ báo rõ và để employer tìm địa chỉ thủ công).
  Future<void> _useGpsLocation() async {
    setState(() {
      _locatingGps = true;
      _error = null;
      _geocodingError = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _geocodingError = 'Không có quyền vị trí. Bạn có thể tìm địa chỉ thủ công.');
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      // Toạ độ GPS hợp lệ ngay cả khi bước reverse-geocode dưới đây thất bại (mục 5: GPS lỗi
      // mạng không được làm mất toạ độ đã lấy được) - lưu trước, rồi mới thử lấy địa chỉ.
      setState(() {
        _latitude = position.latitude;
        _longitude = position.longitude;
      });
      try {
        final geocodingService = context.read<GeocodingService>();
        final result = await geocodingService.reverse(position.latitude, position.longitude);
        if (!mounted) return;
        if (result != null) {
          setState(() => _applyGeocodingResult(result));
        } else {
          setState(() => _geocodingError = 'Không xác định được địa chỉ tại vị trí này. Vui lòng nhập địa chỉ hoặc chọn khu vực thủ công.');
        }
      } on GeocodingException catch (e) {
        if (!mounted) return;
        setState(() => _geocodingError = 'Lấy được vị trí nhưng ${e.userMessage[0].toLowerCase()}${e.userMessage.substring(1)} Vui lòng nhập địa chỉ hoặc chọn khu vực thủ công.');
      }
    } catch (_) {
      if (mounted) setState(() => _geocodingError = 'Không lấy được vị trí hiện tại. Bạn có thể tìm địa chỉ thủ công.');
    } finally {
      if (mounted) setState(() => _locatingGps = false);
    }
  }

  Future<void> _save() async {
    // Bug thật: nút LƯU HỒ SƠ chỉ bị khoá qua `onPressed: _saving ? null : _save` - nếu 2 lần
    // bấm xảy ra trước khi widget kịp rebuild (vd double-tap thật hoặc test bấm liên tiếp không
    // đợi frame), cả 2 đều gọi trực tiếp _save() và tạo 2 cơ sở trùng lặp. Chặn thêm ngay tại
    // đây, không chỉ dựa vào trạng thái disabled của nút.
    if (_saving) return;
    if (_businessNameController.text.trim().isEmpty ||
        (!_hasExistingLocation && (_addressController.text.trim().isEmpty || !_hasValidLocation))) {
      setState(() => _error = 'Vui lòng nhập tên doanh nghiệp và xác định địa chỉ cơ sở (tìm địa chỉ hoặc dùng vị trí GPS hiện tại).');
      return;
    }
    // areaId vẫn BẮT BUỘC (không bỏ validation - chỉ sửa đúng luồng để areaId có cơ hội được set
    // tự động hoặc chọn thủ công đúng cách, thay vì bị khoá bởi bug hiển thị sai trạng thái).
    if (!_hasExistingLocation && _areaId == null) {
      setState(() => _error = 'Vui lòng chọn khu vực. Hệ thống không tự xác định được khu vực từ địa chỉ này - hãy chọn thủ công ở danh sách bên dưới.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profileService = context.read<EmployerProfileService>();
      await profileService.saveEmployerProfile({
        'businessName': _businessNameController.text.trim(),
        if (_descriptionController.text.trim().isNotEmpty) 'description': _descriptionController.text.trim(),
      });

      // Chỉ tạo cơ sở mới khi CHƯA có cơ sở nào - backend chưa có API cập nhật cơ sở theo id nên
      // gọi lại addEmployerLocation() ở đây sẽ tạo bản ghi TRÙNG LẶP, không phải cập nhật.
      if (!_hasExistingLocation) {
        final area = _areas.firstWhere((a) => a.id == _areaId);
        await profileService.addEmployerLocation({
          'name': _locationNameController.text.trim().isEmpty ? _businessNameController.text.trim() : _locationNameController.text.trim(),
          'address': _addressController.text.trim(),
          'cityId': _cityId,
          'areaId': area.id,
          'latitude': _latitude,
          'longitude': _longitude,
          if (_phoneController.text.trim().isNotEmpty) 'phone': _phoneController.text.trim(),
        });
      }

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // Đặc tả §4: SĐT TÀI KHOẢN (khác SĐT liên hệ cơ sở ở form bên dưới) hiển thị trạng thái xác
  // minh thật, không đánh dấu "đã xác minh" chỉ vì có SĐT - phải qua OTP thật.
  Future<void> _verifyAccountPhone() async {
    final verified = await showPhoneVerificationSheet(context);
    if (verified == true) _loadAreas();
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingExisting) {
      return Scaffold(
        appBar: AppBar(title: const Text('Hồ sơ doanh nghiệp')),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ doanh nghiệp')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: ListTile(
              leading: Icon(
                _me?['isPhoneVerified'] == true ? Icons.verified : Icons.phone_outlined,
                color: _me?['isPhoneVerified'] == true ? Colors.green : null,
              ),
              title: Text(_me?['phone'] ?? 'Chưa có số điện thoại tài khoản'),
              subtitle: Text(_me?['isPhoneVerified'] == true ? 'Đã xác minh' : 'Chưa xác minh - cần trước khi đăng tuyển'),
              trailing: _me?['isPhoneVerified'] == true
                  ? null
                  : TextButton(onPressed: _verifyAccountPhone, child: const Text('XÁC MINH')),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _businessNameController,
            decoration: const InputDecoration(labelText: 'Tên cửa hàng/doanh nghiệp', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _descriptionController,
            maxLines: 3,
            decoration: const InputDecoration(labelText: 'Mô tả doanh nghiệp (không bắt buộc)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          const Text('Thông tin cơ sở', style: TextStyle(fontWeight: FontWeight.bold)),
          if (_hasExistingLocation) ...[
            const SizedBox(height: 4),
            const Text(
              'Đã có cơ sở được lưu - hiển thị lại đúng dữ liệu thật. Backend chưa hỗ trợ sửa cơ sở đã tạo (chỉ tạo mới), nên các trường bên dưới tạm khoá.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _locationNameController,
            enabled: !_hasExistingLocation,
            decoration: const InputDecoration(labelText: 'Tên cơ sở (vd: Chi nhánh Vĩnh Hải)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            enabled: !_hasExistingLocation,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Số điện thoại cơ sở (không bắt buộc)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 20),
          const Text('Vị trí cơ sở', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Tìm địa chỉ hoặc dùng vị trí GPS hiện tại - hệ thống tự lấy toạ độ và tự xác định khu vực, không cần tự nhập toạ độ.',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _addressController,
            enabled: !_hasExistingLocation,
            decoration: const InputDecoration(
              labelText: 'Địa chỉ (vd: 37 Hồng Bàng, Nha Trang)',
              hintText: 'Nhập địa chỉ rồi bấm TÌM ĐỊA ĐIỂM',
              border: OutlineInputBorder(),
            ),
            onSubmitted: _hasExistingLocation ? null : (_) => _searchAddress(),
          ),
          const SizedBox(height: 8),
          if (!_hasExistingLocation)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _searching ? null : _searchAddress,
                    icon: _searching
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.search),
                    label: const Text('TÌM ĐỊA ĐIỂM'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _locatingGps ? null : _useGpsLocation,
                    icon: _locatingGps
                        ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.my_location),
                    label: const Text('DÙNG VỊ TRÍ HIỆN TẠI'),
                  ),
                ),
              ],
            ),
          if (_searchResults.isNotEmpty) ...[
            const SizedBox(height: 8),
            Card(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: _searchResults
                    .map((r) => ListTile(
                          leading: const Icon(Icons.place_outlined),
                          title: Text(r.displayName, maxLines: 2, overflow: TextOverflow.ellipsis),
                          onTap: () => _selectSearchResult(r),
                        ))
                    .toList(),
              ),
            ),
          ],
          if (_geocodingError != null) ...[
            const SizedBox(height: 8),
            Text(_geocodingError!, style: TextStyle(color: Colors.orange.shade800)),
          ],
          const SizedBox(height: 8),
          Text(
            _hasValidLocation
                ? 'Đã xác định vị trí cơ sở.'
                : 'Chưa có vị trí. Hãy tìm địa chỉ hoặc dùng vị trí GPS hiện tại trước khi lưu.',
            style: TextStyle(
              color: _hasValidLocation ? Colors.green.shade700 : Colors.orange.shade800,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 20),
          const Text('Khu vực', style: TextStyle(fontWeight: FontWeight.w600)),
          const SizedBox(height: 4),
          if (_areaAutoMatched)
            Text('Khu vực đã được tự động xác định từ địa chỉ.', style: TextStyle(color: Colors.green.shade700, fontSize: 12))
          else if (_hasValidLocation && _areaId == null && !_hasExistingLocation)
            Text('Khu vực chưa được xác định tự động. Vui lòng chọn bên dưới.', style: TextStyle(color: Colors.orange.shade800, fontSize: 12)),
          const SizedBox(height: 8),
          // Thay DropdownButtonFormField bằng ô tìm kiếm + ChoiceChip (đặc tả Phase F: gõ
          // "Vĩnh Hải"/"Lộc Thọ" phải lọc đúng khu vực đó) - Dropdown không hỗ trợ lọc sẵn, và
          // lọc items trong khi vẫn giữ value đã chọn ngoài danh sách lọc sẽ gây assertion lỗi.
          if (_areas.length > 6 && !_hasExistingLocation) ...[
            TextField(
              controller: _areaSearchController,
              decoration: const InputDecoration(
                hintText: 'Tìm khu vực (vd: Vĩnh Hải, Lộc Thọ)',
                prefixIcon: Icon(Icons.search),
                border: OutlineInputBorder(),
                isDense: true,
              ),
              onChanged: (v) => setState(() => _areaSearchQuery = v),
            ),
            const SizedBox(height: 8),
          ],
          if (_hasExistingLocation)
            Chip(label: Text(_areas.firstWhere((a) => a.id == _areaId, orElse: () => Area(id: '', name: 'Không xác định')).name))
          else if (_areas.isEmpty)
            // Root cause bug thật (xem docstring đầu file): trước đây nhánh này bị gộp chung với
            // "search không khớp" bên dưới, hiển thị nhầm "Không tìm thấy khu vực phù hợp." dù
            // người dùng chưa hề gõ tìm kiếm gì - thực chất là /areas CHƯA TẢI ĐƯỢC. Tách riêng +
            // có nút THỬ LẠI thật (gọi lại _loadAreas(), không phải chỉ đổi text).
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _areasLoadError != null ? 'Chưa tải được danh sách khu vực. ${_areasLoadError!.userMessage}' : 'Chưa có dữ liệu khu vực.',
                  style: const TextStyle(color: Colors.black54),
                ),
                TextButton(onPressed: _loadAreas, child: const Text('THỬ LẠI')),
              ],
            )
          else if (_filteredAreas.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Không tìm thấy khu vực phù hợp.', style: TextStyle(color: Colors.black54)),
            )
          else
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: _filteredAreas
                  .map((a) => ChoiceChip(
                        label: Text(a.name),
                        selected: _areaId == a.id,
                        onSelected: (_) => setState(() {
                          _areaId = a.id;
                          _areaAutoMatched = false;
                        }),
                      ))
                  .toList(),
            ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          const SizedBox(height: 24),
          FilledButton(
            onPressed: _saving ? null : _save,
            style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
            child: _saving
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('LƯU HỒ SƠ'),
          ),
        ],
      ),
    );
  }
}
