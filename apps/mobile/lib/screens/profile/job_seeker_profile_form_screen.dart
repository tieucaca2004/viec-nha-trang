import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../services/jobs_service.dart';
import '../../services/profile_service.dart';
import '../../models/job.dart';

/// Hồ sơ tìm việc tối giản (đặc tả mục 11): họ tên, khu vực, ngành nghề mong muốn,
/// kinh nghiệm, ca có thể làm, mức lương mong muốn. Không bắt buộc CV.
class JobSeekerProfileFormScreen extends StatefulWidget {
  final Map<String, dynamic>? existing;
  const JobSeekerProfileFormScreen({super.key, this.existing});

  @override
  State<JobSeekerProfileFormScreen> createState() => _JobSeekerProfileFormScreenState();
}

class _JobSeekerProfileFormScreenState extends State<JobSeekerProfileFormScreen> {
  final _fullNameController = TextEditingController();
  final _salaryMinController = TextEditingController();
  final _salaryMaxController = TextEditingController();
  List<JobCategory> _categories = [];
  List<Area> _areas = [];
  String? _selectedCategoryId;
  String? _selectedAreaId;
  String _experienceLevel = 'NONE';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _fullNameController.text = widget.existing?['fullName'] ?? '';
    _selectedCategoryId = widget.existing?['desiredCategoryId'];
    _selectedAreaId = widget.existing?['areaId'];
    _experienceLevel = widget.existing?['experienceLevel'] ?? 'NONE';
    _salaryMinController.text = widget.existing?['desiredSalaryMin']?.toString() ?? '';
    _salaryMaxController.text = widget.existing?['desiredSalaryMax']?.toString() ?? '';
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    final jobsService = context.read<JobsService>();
    final categories = await jobsService.categories();
    final areas = await jobsService.areas();
    setState(() {
      _categories = categories;
      _areas = areas;
    });
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<ProfileService>().saveJobSeekerProfile({
        'fullName': _fullNameController.text.trim(),
        'desiredCategoryId': _selectedCategoryId,
        'areaId': _selectedAreaId,
        'experienceLevel': _experienceLevel,
        'shiftPreferences': ['FLEXIBLE'],
        'desiredSalaryMin': int.tryParse(_salaryMinController.text),
        'desiredSalaryMax': int.tryParse(_salaryMaxController.text),
        'salaryUnit': 'HOUR',
      });
      if (!mounted) return;
      Navigator.of(context).pop();
    } finally {
      setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hồ sơ tìm việc')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _fullNameController,
            decoration: const InputDecoration(labelText: 'Họ và tên', border: OutlineInputBorder()),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedCategoryId,
            decoration: const InputDecoration(labelText: 'Ngành nghề mong muốn', border: OutlineInputBorder()),
            items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
            onChanged: (v) => setState(() => _selectedCategoryId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _selectedAreaId,
            decoration: const InputDecoration(labelText: 'Khu vực đang ở', border: OutlineInputBorder()),
            items: _areas.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
            onChanged: (v) => setState(() => _selectedAreaId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            initialValue: _experienceLevel,
            decoration: const InputDecoration(labelText: 'Kinh nghiệm', border: OutlineInputBorder()),
            items: const [
              DropdownMenuItem(value: 'NONE', child: Text('Chưa có kinh nghiệm')),
              DropdownMenuItem(value: 'UNDER_1_YEAR', child: Text('Dưới 1 năm')),
              DropdownMenuItem(value: 'ONE_TO_3_YEARS', child: Text('1-3 năm')),
              DropdownMenuItem(value: 'OVER_3_YEARS', child: Text('Trên 3 năm')),
            ],
            onChanged: (v) => setState(() => _experienceLevel = v ?? 'NONE'),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _salaryMinController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Lương mong muốn từ (đ/giờ)', border: OutlineInputBorder()),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: _salaryMaxController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Đến', border: OutlineInputBorder()),
                ),
              ),
            ],
          ),
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
