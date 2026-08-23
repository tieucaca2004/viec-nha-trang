import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/job.dart';
import '../../../shared/utils/normalize_vi.dart';
import '../../jobs/data/jobs_service.dart';
import '../data/employer_profile_service.dart';
import '../../auth/data/auth_service.dart';
import '../../../shared/widgets/phone_verification_sheet.dart';

/// Tạo hồ sơ doanh nghiệp/cơ sở (đặc tả §18 Phase 3, §13 gốc bước chuẩn bị).
/// SĐT tài khoản (khác SĐT liên hệ của cơ sở bên dưới) hiển thị trạng thái xác minh thật từ /me -
/// từ khi đăng ký chuyển sang dùng email (đặc tả §1 phase kế tiếp), SĐT KHÔNG còn tự động
/// verified nữa, phải xác minh riêng khi cần đăng tuyển (đặc tả §3/§4).
///
/// Sửa lỗi High #8 (FULL AUDIT): trước đây lat/lng luôn hard-code toạ độ trung tâm Nha Trang,
/// sai với mọi cơ sở không thực sự nằm đúng điểm đó (làm sai tính năng "khoảng cách" cho seeker).
/// Bây giờ employer PHẢI tự cung cấp vị trí thật bằng 1 trong 2 cách: (a) GPS hiện tại qua
/// [Geolocator] (đã dùng sẵn ở home_screen.dart, cùng 1 pattern permission không chặn app), hoặc
/// (c) tự nhập toạ độ. KHÔNG có bản đồ tương tác (Google Maps) ở đây - đặc tả gốc §18/§37 cấm
/// thêm Maps billing/config khi chưa có credentials thật trong môi trường này; nhập toạ độ thủ
/// công là fallback thật, không phải giả vờ có map. Xem docs/MOBILE.md để biết yêu cầu còn thiếu
/// (map picker thật) khi có Maps API key + billing account thật.
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
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  List<Area> _areas = [];
  String? _areaId;
  String? _cityId;
  final _areaSearchController = TextEditingController();
  String _areaSearchQuery = '';

  // Search client-side trên danh sách Area (phường/xã cũ) đã tải sẵn - không phân biệt
  // dấu/hoa-thường (đặc tả: gõ "Vĩnh Hải" hoặc "vinh hai" đều phải lọc ra đúng Vĩnh Hải).
  List<Area> get _filteredAreas {
    if (_areaSearchQuery.trim().isEmpty) return _areas;
    final normalizedQuery = normalizeVietnamese(_areaSearchQuery);
    return _areas.where((a) => normalizeVietnamese(a.name).contains(normalizedQuery)).toList();
  }
  bool _saving = false;
  bool _loadingExisting = true;
  bool _locatingGps = false;
  // Backend chưa có API cập nhật cơ sở đã tạo (chỉ có GET/POST /me/employer-profile/locations,
  // không có PATCH/PUT theo id) - nếu đã có cơ sở, khoá phần vị trí để tránh tạo trùng lặp thay
  // vì âm thầm POST thêm 1 bản ghi mới. Xem báo cáo cuối để biết endpoint backend cần bổ sung.
  bool _hasExistingLocation = false;
  Map<String, dynamic>? _me;
  String? _error;

  double? get _latitude => double.tryParse(_latitudeController.text.trim());
  double? get _longitude => double.tryParse(_longitudeController.text.trim());
  bool get _hasValidLocation {
    final lat = _latitude;
    final lng = _longitude;
    return lat != null && lng != null && lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;
  }

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
    _latitudeController.dispose();
    _longitudeController.dispose();
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
      if (areasResult is! ApiException) _areas = areasResult as List<Area>;
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
        if (lat != null) _latitudeController.text = (lat as num).toStringAsFixed(6);
        if (lng != null) _longitudeController.text = (lng as num).toStringAsFixed(6);
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

  /// Lấy vị trí GPS hiện tại - cùng pattern permission không chặn app như home_screen.dart
  /// (§22 gốc: từ chối quyền không được crash/chặn luồng, chỉ báo rõ và để employer tự nhập).
  Future<void> _useGpsLocation() async {
    setState(() {
      _locatingGps = true;
      _error = null;
    });
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        if (mounted) {
          setState(() => _error = 'Bạn chưa cấp quyền vị trí. Hãy tự nhập toạ độ hoặc cấp quyền rồi thử lại.');
        }
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      if (!mounted) return;
      setState(() {
        _latitudeController.text = position.latitude.toStringAsFixed(6);
        _longitudeController.text = position.longitude.toStringAsFixed(6);
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Không lấy được vị trí GPS. Hãy tự nhập toạ độ.');
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
    if (_businessNameController.text.trim().isEmpty || _areaId == null) {
      setState(() => _error = 'Vui lòng nhập tên doanh nghiệp và chọn khu vực.');
      return;
    }
    // Chỉ bắt buộc vị trí hợp lệ khi CHƯA có cơ sở nào (tạo mới) - nếu đã có, phần vị trí bị khoá
    // (không gửi lại) nên không cần validate lại toạ độ cũ.
    if (!_hasExistingLocation && !_hasValidLocation) {
      setState(() => _error = 'Vui lòng xác định vị trí cơ sở: dùng GPS hiện tại hoặc tự nhập toạ độ hợp lệ trước khi lưu.');
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
            controller: _addressController,
            enabled: !_hasExistingLocation,
            decoration: const InputDecoration(labelText: 'Địa chỉ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            enabled: !_hasExistingLocation,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Số điện thoại cơ sở (không bắt buộc)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          const Text('Khu vực', style: TextStyle(fontWeight: FontWeight.w600)),
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
                        onSelected: (_) => setState(() => _areaId = a.id),
                      ))
                  .toList(),
            ),
          const SizedBox(height: 20),
          const Text('Vị trí cơ sở', style: TextStyle(fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          const Text(
            'Vị trí thật (không phải mặc định) để seeker tìm được đúng khoảng cách tới cơ sở của bạn.',
            style: TextStyle(color: Colors.black54, fontSize: 12),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: (_locatingGps || _hasExistingLocation) ? null : _useGpsLocation,
            icon: _locatingGps
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.my_location),
            label: const Text('DÙNG VỊ TRÍ GPS HIỆN TẠI'),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _latitudeController,
                  enabled: !_hasExistingLocation,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Vĩ độ (latitude)', border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _longitudeController,
                  enabled: !_hasExistingLocation,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Kinh độ (longitude)', border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _hasValidLocation
                ? 'Vị trí đã chọn: ${_latitude!.toStringAsFixed(6)}, ${_longitude!.toStringAsFixed(6)}${_addressController.text.trim().isEmpty ? '' : ' — ${_addressController.text.trim()}'}'
                : 'Chưa có vị trí. Hãy dùng GPS hoặc tự nhập toạ độ trước khi lưu.',
            style: TextStyle(
              color: _hasValidLocation ? Colors.green.shade700 : Colors.orange.shade800,
              fontWeight: FontWeight.w600,
            ),
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
