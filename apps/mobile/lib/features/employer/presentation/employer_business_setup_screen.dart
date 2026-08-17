import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/job.dart';
import '../../jobs/data/jobs_service.dart';
import '../data/employer_profile_service.dart';

/// Tạo hồ sơ doanh nghiệp/cơ sở (đặc tả §18 Phase 3, §13 gốc bước chuẩn bị).
/// SĐT đã được xác minh qua OTP khi đăng nhập nên bước "xác minh SĐT" coi như hoàn tất.
///
/// Ghi chú API gap (§23/§31): chưa có chọn vị trí trên bản đồ ở mobile - dùng tọa độ trung
/// tâm Nha Trang làm mặc định. Backend đã lưu đúng lat/lng theo cơ sở (docs/DATABASE.md);
/// việc còn thiếu là UI chọn bản đồ, không phải giới hạn backend - xem docs/MOBILE.md.
class EmployerBusinessSetupScreen extends StatefulWidget {
  const EmployerBusinessSetupScreen({super.key});

  @override
  State<EmployerBusinessSetupScreen> createState() => _EmployerBusinessSetupScreenState();
}

class _EmployerBusinessSetupScreenState extends State<EmployerBusinessSetupScreen> {
  final _businessNameController = TextEditingController();
  final _locationNameController = TextEditingController();
  final _addressController = TextEditingController();
  List<Area> _areas = [];
  String? _areaId;
  String? _cityId;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAreas();
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

  Future<void> _save() async {
    if (_businessNameController.text.trim().isEmpty || _areaId == null) {
      setState(() => _error = 'Vui lòng nhập tên doanh nghiệp và chọn khu vực.');
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
        'latitude': 12.2388,
        'longitude': 109.1967,
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
