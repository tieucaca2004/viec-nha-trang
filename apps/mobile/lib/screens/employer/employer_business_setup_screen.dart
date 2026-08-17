import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/jobs_service.dart';
import '../../services/profile_service.dart';
import '../../models/job.dart';

/// Tạo hồ sơ doanh nghiệp/cơ sở + xác minh SĐT (đặc tả mục 13 bước chuẩn bị, mục 20).
/// SĐT đã được xác minh qua OTP khi đăng nhập nên bước "xác minh SĐT" coi như hoàn tất.
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

  @override
  void initState() {
    super.initState();
    _loadAreas();
  }

  Future<void> _loadAreas() async {
    final jobsService = context.read<JobsService>();
    final areas = await jobsService.areas();
    final cities = await jobsService.cities();
    setState(() {
      _areas = areas;
      _cityId = cities.isNotEmpty ? cities.first['id'] as String : null;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      final profileService = context.read<ProfileService>();
      await profileService.saveEmployerProfile({'businessName': _businessNameController.text.trim()});

      final area = _areas.firstWhere((a) => a.id == _areaId);
      await profileService.addEmployerLocation({
        'name': _locationNameController.text.trim().isEmpty ? _businessNameController.text.trim() : _locationNameController.text.trim(),
        'address': _addressController.text.trim(),
        'cityId': _cityId,
        'areaId': area.id,
        // Tọa độ mặc định trung tâm Nha Trang; V1 mobile chọn trên bản đồ sẽ thay giá trị này.
        'latitude': 12.2388,
        'longitude': 109.1967,
      });

      if (!mounted) return;
      Navigator.of(context).pop(true);
    } finally {
      setState(() => _saving = false);
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
            initialValue: _areaId,
            decoration: const InputDecoration(labelText: 'Khu vực', border: OutlineInputBorder()),
            items: _areas.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
            onChanged: (v) => setState(() => _areaId = v),
          ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: (_saving || _businessNameController.text.isEmpty || _areaId == null) ? null : _save,
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
