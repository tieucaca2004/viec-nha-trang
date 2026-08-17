import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/job.dart';
import '../../jobs/data/jobs_service.dart';
import '../data/job_seeker_profile_service.dart';

/// Hồ sơ tìm việc tối giản (đặc tả §16 Phase 3, §11 gốc): họ tên, khu vực, ngành nghề mong
/// muốn, kinh nghiệm, ca có thể làm, mức lương mong muốn. Không bắt buộc CV.
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
  String? _error;

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
    try {
      final categories = await jobsService.categories();
      final areas = await jobsService.areas();
      if (!mounted) return;
      setState(() {
        _categories = categories;
        _areas = areas;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e.userMessage);
    }
  }

  Future<void> _save() async {
    if (_fullNameController.text.trim().isEmpty) {
      setState(() => _error = 'Vui lòng nhập họ tên.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await context.read<JobSeekerProfileService>().saveJobSeekerProfile({
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
    } on ApiException catch (e) {
      setState(() => _error = e.userMessage);
    } finally {
      if (mounted) setState(() => _saving = false);
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
            value: _selectedCategoryId,
            decoration: const InputDecoration(labelText: 'Ngành nghề mong muốn', border: OutlineInputBorder()),
            items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
            onChanged: (v) => setState(() => _selectedCategoryId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _selectedAreaId,
            decoration: const InputDecoration(labelText: 'Khu vực đang ở', border: OutlineInputBorder()),
            items: _areas.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
            onChanged: (v) => setState(() => _selectedAreaId = v),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            value: _experienceLevel,
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
