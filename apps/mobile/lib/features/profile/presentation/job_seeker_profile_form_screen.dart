import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/job.dart';
import '../../jobs/data/jobs_service.dart';
import '../data/job_seeker_profile_service.dart';

/// Đơn vị lương mong muốn - khớp đúng enum SalaryUnit của backend (Prisma + DTO), không thêm
/// giá trị mới. Nhãn hiển thị tiếng Việt cho người dùng.
const _salaryUnitLabels = {
  'HOUR': 'Giờ',
  'DAY': 'Ngày',
  'SHIFT': 'Ca',
  'MONTH': 'Tháng',
};

/// Riêng lương THÁNG được nhập theo TRIỆU đồng cho dễ đọc/dễ gõ (8.5 thay vì 8500000), rồi quy
/// đổi sang VND trước khi gửi - backend vẫn nhận số nguyên VND như cũ, không đổi API/schema.
/// Các đơn vị còn lại (giờ/ngày/ca) giữ nguyên cách nhập thẳng số VND vì giá trị vốn đã nhỏ
/// (vd 25.000đ/giờ), quy ra triệu sẽ thành 0.025 - khó nhập và dễ sai hơn.
const _millionUnit = 'MONTH';
const _vndPerMillion = 1000000;

/// Chặn nhập nhầm cỡ lớn (gõ thừa số 0). 1 tỷ đồng phủ xa mọi mức lương thực tế ở mọi đơn vị.
const _maxSalaryVnd = 1000000000;

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
  String _salaryUnit = 'HOUR';
  bool _saving = false;
  bool _loadingOptions = true;
  String? _error;

  bool get _salaryInMillions => _salaryUnit == _millionUnit;

  /// Số VND đã lưu -> chuỗi hiển thị trong ô nhập, theo đúng đơn vị đang chọn.
  /// Với đơn vị THÁNG: 8500000 -> "8.5", 12000000 -> "12" (không để thừa ".0").
  String _salaryToInput(Object? storedVnd) {
    if (storedVnd is! num) return '';
    if (!_salaryInMillions) return storedVnd.toInt().toString();
    final millions = storedVnd / _vndPerMillion;
    return millions == millions.roundToDouble() ? millions.toInt().toString() : millions.toString();
  }

  /// Chuỗi trong ô nhập -> số nguyên VND gửi lên backend. Trả null khi ô trống (trường optional).
  /// Ném [FormatException] khi nội dung không phải số hợp lệ - KHÔNG âm thầm biến thành 0/null
  /// như code cũ (int.tryParse("8.5") trả null rồi gửi thẳng null, mất dữ liệu mà không báo).
  int? _salaryToVnd(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    // Người dùng VN có thể gõ dấu phẩy làm dấu thập phân ("8,5").
    final normalized = trimmed.replaceAll(',', '.');
    final value = double.tryParse(normalized);
    if (value == null) throw const FormatException('Lương mong muốn không hợp lệ.');
    // round() trước khi toInt(): 8.5 * 1000000 phải ra đúng 8500000, không bị 8499999 do sai số
    // dấu phẩy động.
    return _salaryInMillions ? (value * _vndPerMillion).round() : value.round();
  }

  String get _salaryFieldSuffix => _salaryInMillions ? 'triệu/tháng' : 'đ/${_salaryUnitLabels[_salaryUnit]!.toLowerCase()}';

  @override
  void initState() {
    super.initState();
    _fullNameController.text = widget.existing?['fullName'] ?? '';
    _selectedCategoryId = widget.existing?['desiredCategoryId'];
    _selectedAreaId = widget.existing?['areaId'];
    _experienceLevel = widget.existing?['experienceLevel'] ?? 'NONE';
    // Đơn vị phải đọc TRƯỚC khi quy đổi 2 ô lương - hồ sơ cũ lưu theo giờ (vd 25000đ/giờ) không
    // được chia cho 1 triệu, chỉ hồ sơ theo tháng mới hiển thị dạng triệu.
    final storedUnit = widget.existing?['salaryUnit'];
    if (storedUnit is String && _salaryUnitLabels.containsKey(storedUnit)) _salaryUnit = storedUnit;
    _salaryMinController.text = _salaryToInput(widget.existing?['desiredSalaryMin']);
    _salaryMaxController.text = _salaryToInput(widget.existing?['desiredSalaryMax']);
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

    // Cùng lớp lỗi với wizard đăng tin: trước đây categories/areas await tuần tự trong 1 try/catch
    // nên /areas lỗi là mất luôn danh sách ngành nghề đã tải được. Chạy song song + tách lỗi.
    final results = await Future.wait<Object?>([
      _safeCall(jobsService.categories()),
      _safeCall(jobsService.areas()),
    ]);
    if (!mounted) return;

    final categoriesResult = results[0];
    final areasResult = results[1];
    setState(() {
      if (categoriesResult is List<JobCategory>) _categories = categoriesResult;
      if (areasResult is List<Area>) _areas = areasResult;
      final failed = results.whereType<ApiException>().toList();
      _error = failed.isEmpty ? null : failed.first.userMessage;
      _loadingOptions = false;
    });
  }

  Future<Object?> _safeCall(Future<Object?> future) async {
    try {
      return await future;
    } on ApiException catch (e) {
      return e;
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

  /// Kiểm tra 2 ô lương, trả về cặp (min, max) tính bằng VND. Ném [FormatException] kèm thông báo
  /// hiển thị được cho người dùng nếu dữ liệu sai - để trống là hợp lệ (trường optional).
  (int?, int?) _validatedSalaryVnd() {
    final min = _salaryToVnd(_salaryMinController.text);
    final max = _salaryToVnd(_salaryMaxController.text);
    for (final value in [min, max]) {
      if (value == null) continue;
      if (value <= 0) throw const FormatException('Lương mong muốn phải lớn hơn 0.');
      if (value > _maxSalaryVnd) throw const FormatException('Lương mong muốn quá lớn, vui lòng kiểm tra lại.');
    }
    if (min != null && max != null && min > max) {
      throw const FormatException('Lương mong muốn tối thiểu không được lớn hơn mức tối đa.');
    }
    return (min, max);
  }

  Future<void> _save() async {
    if (_fullNameController.text.trim().isEmpty) {
      setState(() => _error = 'Vui lòng nhập họ tên.');
      return;
    }
    final int? salaryMinVnd;
    final int? salaryMaxVnd;
    try {
      (salaryMinVnd, salaryMaxVnd) = _validatedSalaryVnd();
    } on FormatException catch (e) {
      setState(() => _error = e.message);
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
        'desiredSalaryMin': salaryMinVnd,
        'desiredSalaryMax': salaryMaxVnd,
        'salaryUnit': _salaryUnit,
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
          // Đơn vị lương phải chọn được: trước đây mobile hard-code salaryUnit:'HOUR' nên không có
          // cách nào khai lương theo tháng, dù backend đã hỗ trợ sẵn enum SalaryUnit đầy đủ.
          // Backend chỉ cộng điểm phù hợp lương khi đơn vị của ứng viên trùng đơn vị của tin
          // tuyển dụng (match-score.service.ts), nên đơn vị phải phản ánh đúng ý người dùng.
          DropdownButtonFormField<String>(
            key: const Key('salaryUnitField'),
            value: _salaryUnit,
            decoration: const InputDecoration(labelText: 'Đơn vị lương', border: OutlineInputBorder()),
            items: _salaryUnitLabels.entries
                .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
                .toList(),
            onChanged: (v) {
              if (v == null || v == _salaryUnit) return;
              // Đổi đơn vị làm đổi luôn ý nghĩa con số đang gõ dở (25000 đ/giờ vs 8.5 triệu/tháng)
              // - giữ lại sẽ thành dữ liệu sai. Xoá 2 ô để người dùng nhập lại theo đơn vị mới.
              setState(() {
                _salaryUnit = v;
                _salaryMinController.clear();
                _salaryMaxController.clear();
              });
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  key: const Key('desiredSalaryMinField'),
                  controller: _salaryMinController,
                  keyboardType: TextInputType.numberWithOptions(decimal: _salaryInMillions),
                  // Chặn chữ/ký tự lạ ngay khi nhập. Đơn vị tháng cho phép 1 dấu thập phân
                  // (chấm hoặc phẩy) để gõ được 8.5; các đơn vị khác chỉ nhận số nguyên VND.
                  // Dấu trừ luôn bị chặn - backend yêu cầu @Min(0).
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(_salaryInMillions ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Lương mong muốn từ',
                    suffixText: _salaryFieldSuffix,
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  key: const Key('desiredSalaryMaxField'),
                  controller: _salaryMaxController,
                  keyboardType: TextInputType.numberWithOptions(decimal: _salaryInMillions),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(_salaryInMillions ? RegExp(r'[0-9.,]') : RegExp(r'[0-9]')),
                  ],
                  decoration: InputDecoration(
                    labelText: 'Đến',
                    suffixText: _salaryFieldSuffix,
                    border: const OutlineInputBorder(),
                  ),
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
