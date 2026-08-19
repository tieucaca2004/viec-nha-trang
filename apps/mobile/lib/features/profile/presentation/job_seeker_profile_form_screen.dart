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
  DateTime? _dateOfBirth;
  bool _saving = false;
  bool _loadingOptions = true;
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
    // Ngày sinh (đặc tả §2 - trường optional): chỉ parse khi backend thật sự có giá trị, để
    // trống nếu chưa từng nhập - không tự chế giá trị mặc định.
    final rawDob = widget.existing?['dateOfBirth'];
    if (rawDob is String && rawDob.isNotEmpty) {
      _dateOfBirth = DateTime.tryParse(rawDob);
    }
    _loadOptions();
  }

  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _error = null;
    });
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
    } finally {
      if (mounted) setState(() => _loadingOptions = false);
    }
  }

  // Ngày sinh (đặc tả §2): không cho chọn ngày tương lai - chặn ngay ở lastDate của date picker
  // (thời điểm hiện tại), không phải chỉ validate sau khi chọn xong.
  Future<void> _pickDateOfBirth() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _dateOfBirth ?? DateTime(now.year - 20, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: now,
    );
    if (picked != null) {
      setState(() => _dateOfBirth = picked);
    }
  }

  String _formatDob(DateTime date) {
    return '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
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
        // Chỉ gửi key khi thật sự có giá trị (trường optional) - không gửi null đè lên dữ liệu đã
        // lưu, và DTO backend dùng @IsOptional (undefined bỏ qua validate, null sẽ lỗi @IsDateString).
        if (_dateOfBirth != null) 'dateOfBirth': _dateOfBirth!.toIso8601String().split('T').first,
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
          // Ngành nghề mong muốn / Khu vực - dữ liệu thật từ Categories/Areas API (đặc tả §2A/§2B).
          // Backend chỉ hỗ trợ chọn 1 ngành nghề (field desiredCategoryId đơn giá trị trong DTO),
          // không có API multi-select nên không dựng UI chọn nhiều ở đây.
          if (_loadingOptions)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            DropdownButtonFormField<String>(
              value: _selectedCategoryId,
              decoration: const InputDecoration(labelText: 'Ngành nghề mong muốn', border: OutlineInputBorder()),
              items: _categories.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
              onChanged: _categories.isEmpty ? null : (v) => setState(() => _selectedCategoryId = v),
            ),
            if (_categories.isEmpty && _error == null) ...[
              const SizedBox(height: 4),
              const Text(
                'Chưa có danh sách ngành nghề từ hệ thống. Vui lòng thử lại sau.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              value: _selectedAreaId,
              decoration: const InputDecoration(labelText: 'Khu vực đang ở', border: OutlineInputBorder()),
              items: _areas.map((a) => DropdownMenuItem(value: a.id, child: Text(a.name))).toList(),
              onChanged: _areas.isEmpty ? null : (v) => setState(() => _selectedAreaId = v),
            ),
            if (_areas.isEmpty && _error == null) ...[
              const SizedBox(height: 4),
              const Text(
                'Chưa có danh sách khu vực từ hệ thống. Vui lòng thử lại sau.',
                style: TextStyle(color: Colors.black54, fontSize: 12),
              ),
            ],
          ],
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
          InkWell(
            key: const Key('dobField'),
            onTap: _pickDateOfBirth,
            child: InputDecorator(
              decoration: const InputDecoration(labelText: 'Ngày sinh', border: OutlineInputBorder()),
              child: Text(
                _dateOfBirth != null ? _formatDob(_dateOfBirth!) : 'Chưa chọn',
                style: TextStyle(color: _dateOfBirth != null ? null : Colors.black54),
              ),
            ),
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
            if (_categories.isEmpty && _areas.isEmpty) ...[
              const SizedBox(height: 8),
              OutlinedButton(onPressed: _loadOptions, child: const Text('THỬ LẠI')),
            ],
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
