import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/job.dart';
import '../../jobs/data/jobs_service.dart';
import '../data/employer_profile_service.dart';

/// Tạo hồ sơ doanh nghiệp/cơ sở (đặc tả §18 Phase 3, §13 gốc bước chuẩn bị).
/// SĐT đã được xác minh qua OTP khi đăng nhập nên bước "xác minh SĐT" coi như hoàn tất.
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
  final _locationNameController = TextEditingController();
  final _addressController = TextEditingController();
  final _latitudeController = TextEditingController();
  final _longitudeController = TextEditingController();
  List<Area> _areas = [];
  String? _areaId;
  String? _cityId;
  bool _saving = false;
  bool _locatingGps = false;
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
    _locationNameController.dispose();
    _addressController.dispose();
    _latitudeController.dispose();
    _longitudeController.dispose();
    super.dispose();
  }

  Future<void> _loadAreas() async {
    final jobsService = context.read<JobsService>();
    try {
      final areas = await jobsService.areas();
      final cities = await jobsService.cities();
      if (!mounted) return;
      setState(() {
        _areas = areas;
        _cityId = cities.isNotEmpty ? cities.first['id'] as String : null;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
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
    if (_businessNameController.text.trim().isEmpty || _areaId == null) {
      setState(() => _error = 'Vui lòng nhập tên doanh nghiệp và chọn khu vực.');
      return;
    }
    if (!_hasValidLocation) {
      setState(() => _error = 'Vui lòng xác định vị trí cơ sở: dùng GPS hiện tại hoặc tự nhập toạ độ hợp lệ trước khi lưu.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final profileService = context.read<EmployerProfileService>();
      await profileService.saveEmployerProfile({'businessName': _businessNameController.text.trim()});

      final area = _areas.firstWhere((a) => a.id == _areaId);
      await profileService.addEmployerLocation({
        'name': _locationNameController.text.trim().isEmpty ? _businessNameController.text.trim() : _locationNameController.text.trim(),
        'address': _addressController.text.trim(),
        'cityId': _cityId,
        'areaId': area.id,
        'latitude': _latitude,
        'longitude': _longitude,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ doanh nghiệp')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _businessNameController,
            decoration: const InputDecoration(labelText: 'Tên cửa hàng/doanh nghiệp', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _locationNameController,
            decoration: const InputDecoration(labelText: 'Tên cơ sở (vd: Chi nhánh Vĩnh Hải)', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _addressController,
            decoration: const InputDecoration(labelText: 'Địa chỉ', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _areaId,
            decoration: const InputDecoration(labelText: 'Khu vực', border: OutlineInputBorder()),
            items: _areas.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
            onChanged: (v) => setState(() => _areaId = v),
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
            onPressed: _locatingGps ? null : _useGpsLocation,
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
                  keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true),
                  decoration: const InputDecoration(labelText: 'Vĩ độ (latitude)', border: OutlineInputBorder()),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _longitudeController,
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
