import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/job.dart';
import '../../jobs/data/jobs_service.dart';
import '../data/employer_jobs_service.dart';
import '../data/employer_profile_service.dart';
import '../../../shared/widgets/phone_verification_sheet.dart';
import 'employer_business_setup_screen.dart';

/// Wizard đăng tin cực ngắn - mỗi bước 1 câu hỏi, mục tiêu đăng tin trong 1-2 phút
/// (đặc tả §19 Phase 3). Lương là trường bắt buộc: không cho qua bước nếu thiếu, khớp
/// validation backend (`CreateJobDto.salaryMin/salaryMax` required, docs/API.md).
class PostJobWizardScreen extends StatefulWidget {
  const PostJobWizardScreen({super.key});

  @override
  State<PostJobWizardScreen> createState() => _PostJobWizardScreenState();
}

class _PostJobWizardScreenState extends State<PostJobWizardScreen> {
  final _pageController = PageController();
  int _step = 0;

  List<JobCategory> _categories = [];
  List<dynamic> _locations = [];

  String? _categoryId;
  int _headcount = 1;
  final _salaryMinController = TextEditingController();
  final _salaryMaxController = TextEditingController();
  String _salaryUnit = 'HOUR';
  String _employmentType = 'PART_TIME';
  final Set<String> _shifts = {};
  final _shiftStartController = TextEditingController();
  final _shiftEndController = TextEditingController();
  String? _locationId;
  String _startUrgency = 'NOT_URGENT';
  String _requiredExperience = 'NOT_REQUIRED';
  final _descriptionController = TextEditingController();
  bool _submitting = false;
  bool _loadingOptions = true;
  bool _loadingLocations = false;
  String? _error;

  static const totalSteps = 8;

  @override
  void initState() {
    super.initState();
    _loadOptions();
  }

  // Bug thật trên Beta (bước 1 trắng trơn, TIẾP TỤC bị mờ): trước đây categories và locations được
  // await TUẦN TỰ trong CÙNG 1 try/catch, và setState chỉ chạy SAU cả hai. Chỉ cần
  // myEmployerLocations() lỗi (nhà tuyển dụng mới chưa có cơ sở, mạng chập chờn...) là _categories
  // KHÔNG BAO GIỜ được gán, dù GET /categories đã trả về 37 ngành nghề hợp lệ - bước 1 render 1
  // Wrap rỗng. Sửa: chạy song song, tách lỗi từng phần, phần nào lấy được thì hiển thị phần đó.
  Future<void> _loadOptions() async {
    setState(() {
      _loadingOptions = true;
      _error = null;
    });
    final jobsService = context.read<JobsService>();
    final employerProfileService = context.read<EmployerProfileService>();

    final results = await Future.wait<Object?>([
      _safeCall(jobsService.categories()),
      _safeCall(employerProfileService.myEmployerLocations()),
    ]);
    if (!mounted) return;

    final categoriesResult = results[0];
    final locationsResult = results[1];
    setState(() {
      if (categoriesResult is List<JobCategory>) _categories = categoriesResult;
      if (locationsResult is List) {
        _locations = locationsResult;
        _locationId = locationsResult.isNotEmpty ? locationsResult.first['id'] : null;
      }
      // Chỉ coi là lỗi chặn khi danh sách ngành nghề - dữ liệu BẮT BUỘC của bước 1 - không tải
      // được. Thiếu cơ sở làm việc không chặn wizard: bước chọn địa điểm đã có sẵn hướng dẫn thêm
      // cơ sở mới.
      _error = categoriesResult is ApiException ? categoriesResult.userMessage : null;
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

  // Bug thật trên Beta: nhà tuyển dụng MỚI (chưa có cơ sở nào) bị DEAD-END ở bước 5/8 - màn hình
  // chỉ nói "Bạn chưa có cơ sở nào" mà không có cách nào để tạo cơ sở, TIẾP TỤC mãi mãi bị mờ.
  // EmployerBusinessSetupScreen đã có sẵn (dùng đúng CreateEmployerLocationDto/addEmployerLocation
  // hiện có, kể cả tự tạo employer profile trước nếu cần) - chỉ cần mở nó từ đây và nạp lại danh
  // sách cơ sở khi quay về, KHÔNG reset _step/dữ liệu các bước 1-4 (push, không phải
  // pushReplacement; chỉ _locations/_locationId được cập nhật).
  Future<void> _createLocation() async {
    final created = await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const EmployerBusinessSetupScreen()),
    );
    if (created == true) await _reloadLocations();
  }

  Future<void> _reloadLocations() async {
    setState(() {
      _loadingLocations = true;
      _error = null;
    });
    final employerProfileService = context.read<EmployerProfileService>();
    final result = await _safeCall(employerProfileService.myEmployerLocations());
    if (!mounted) return;
    setState(() {
      if (result is List) {
        _locations = result;
        // Cơ sở vừa tạo là cơ sở DUY NHẤT ngay sau khi từ trạng thái rỗng - tự động chọn luôn,
        // đúng yêu cầu "location vừa tạo tự động chọn nếu phù hợp với architecture hiện tại".
        if (result.isNotEmpty && (_locationId == null || !result.any((l) => l['id'] == _locationId))) {
          _locationId = result.first['id'];
        }
      } else if (result is ApiException) {
        // Tạo cơ sở đã thành công (EmployerBusinessSetupScreen đã pop(true)) - chỉ riêng bước nạp
        // lại danh sách bị lỗi. Báo rõ và cho thử lại, KHÔNG được coi như tạo cơ sở thất bại.
        _error = 'Đã tạo cơ sở nhưng chưa tải lại được danh sách. ${result.userMessage}';
      }
      _loadingLocations = false;
    });
  }

  bool _canGoNext() {
    switch (_step) {
      case 0:
        return _categoryId != null;
      case 2:
        return _salaryMinController.text.isNotEmpty && _salaryMaxController.text.isNotEmpty;
      case 3:
        return _shifts.isNotEmpty;
      case 4:
        return _locationId != null;
      default:
        return true;
    }
  }

  void _next() {
    if (!_canGoNext()) return;
    if (_step < totalSteps - 1) {
      setState(() => _step++);
      _pageController.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    } else {
      _submit();
    }
  }

  void _back() {
    if (_step > 0) {
      setState(() => _step--);
      _pageController.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  Map<String, dynamic> _buildJobPayload() {
    return {
      'employerLocationId': _locationId,
      'categoryId': _categoryId,
      'title': _categories.firstWhere((c) => c.id == _categoryId).name,
      'description': _descriptionController.text.trim(),
      'headcount': _headcount,
      'employmentType': _employmentType,
      'shifts': _shifts.toList(),
      'shiftStartTime': _shiftStartController.text.trim().isEmpty ? null : _shiftStartController.text.trim(),
      'shiftEndTime': _shiftEndController.text.trim().isEmpty ? null : _shiftEndController.text.trim(),
      'salaryMin': int.tryParse(_salaryMinController.text) ?? 0,
      'salaryMax': int.tryParse(_salaryMaxController.text) ?? 0,
      'salaryUnit': _salaryUnit,
      'startUrgency': _startUrgency,
      'requiredExperience': _requiredExperience,
      'isUrgent': _startUrgency == 'IMMEDIATE',
    };
  }

  Future<void> _submit() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await context.read<EmployerJobsService>().createJob(_buildJobPayload());
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } on ApiException catch (e) {
      // Đặc tả §3: backend từ chối đăng tuyển khi số điện thoại chưa xác minh (message cố định
      // 'PHONE_NOT_VERIFIED') - mở sheet xác minh ngay, xong thử đăng tin lại 1 lần.
      if (e.statusCode == 403 && e.rawMessage == 'PHONE_NOT_VERIFIED') {
        if (!mounted) return;
        final verified = await showPhoneVerificationSheet(context);
        if (verified == true && mounted) {
          try {
            await context.read<EmployerJobsService>().createJob(_buildJobPayload());
            if (!mounted) return;
            Navigator.of(context).pop(true);
          } on ApiException catch (e2) {
            if (mounted) setState(() => _error = e2.userMessage);
          }
        }
      } else {
        setState(() => _error = e.userMessage);
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loadingOptions) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Đăng tuyển (${_step + 1}/$totalSteps)'),
        leading: IconButton(icon: const Icon(Icons.arrow_back), onPressed: _step == 0 ? () => Navigator.pop(context) : _back),
      ),
      body: Column(
        children: [
          LinearProgressIndicator(value: (_step + 1) / totalSteps),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _stepCategory(),
                _stepHeadcount(),
                _stepSalary(),
                _stepShift(),
                _stepLocation(),
                _stepUrgency(),
                _stepExperience(),
                _stepDescription(),
              ],
            ),
          ),
          if (_error != null) Padding(padding: const EdgeInsets.all(8), child: Text(_error!, style: const TextStyle(color: Colors.red))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton(
                onPressed: (_canGoNext() && !_submitting) ? _next : null,
                style: FilledButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
                child: _submitting
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                    : Text(_step == totalSteps - 1 ? 'ĐĂNG TIN TUYỂN DỤNG' : 'TIẾP TỤC'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepWrapper(String title, Widget child) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            child,
          ],
        ),
      );

  // Không bao giờ để bước này trắng trơn: tải lỗi -> báo lỗi + nút THỬ LẠI; backend trả rỗng ->
  // nói rõ đang cập nhật danh mục (KHÔNG tự bịa danh sách ngành nghề).
  Widget _stepCategory() => _stepWrapper(
        'Bạn cần tuyển vị trí nào?',
        _categories.isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Chi tiết lỗi từ API hiển thị 1 lần duy nhất ở thanh dưới cùng (_error) - ở đây
                  // chỉ nói rõ bước này đang thiếu gì và cho thao tác thử lại.
                  const Text(
                    'Chưa tải được danh sách ngành nghề.',
                    style: TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 12),
                  OutlinedButton.icon(
                    onPressed: _loadOptions,
                    icon: const Icon(Icons.refresh),
                    label: const Text('THỬ LẠI'),
                  ),
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _categories
                    .map((c) => ChoiceChip(
                          label: Text(c.name),
                          selected: _categoryId == c.id,
                          onSelected: (_) => setState(() => _categoryId = c.id),
                        ))
                    .toList(),
              ),
      );

  Widget _stepHeadcount() => _stepWrapper(
        'Bạn cần bao nhiêu người?',
        Wrap(
          spacing: 8,
          children: [1, 2, 3, 5, 10]
              .map((n) => ChoiceChip(
                    label: Text('$n'),
                    selected: _headcount == n,
                    onSelected: (_) => setState(() => _headcount = n),
                  ))
              .toList(),
        ),
      );

  Widget _stepSalary() => _stepWrapper(
        'Lương bao nhiêu?',
        Column(
          children: [
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _salaryMinController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Từ', border: OutlineInputBorder()),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: TextField(
                    controller: _salaryMaxController,
                    keyboardType: TextInputType.number,
                    onChanged: (_) => setState(() {}),
                    decoration: const InputDecoration(labelText: 'Đến', border: OutlineInputBorder()),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('Giờ'), selected: _salaryUnit == 'HOUR', onSelected: (_) => setState(() => _salaryUnit = 'HOUR')),
                ChoiceChip(label: const Text('Ngày'), selected: _salaryUnit == 'DAY', onSelected: (_) => setState(() => _salaryUnit = 'DAY')),
                ChoiceChip(label: const Text('Tháng'), selected: _salaryUnit == 'MONTH', onSelected: (_) => setState(() => _salaryUnit = 'MONTH')),
                ChoiceChip(label: const Text('Ca'), selected: _salaryUnit == 'SHIFT', onSelected: (_) => setState(() => _salaryUnit = 'SHIFT')),
              ],
            ),
          ],
        ),
      );

  Widget _stepShift() => _stepWrapper(
        'Loại việc & ca làm',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 8,
              children: [
                ChoiceChip(label: const Text('Full-time'), selected: _employmentType == 'FULL_TIME', onSelected: (_) => setState(() => _employmentType = 'FULL_TIME')),
                ChoiceChip(label: const Text('Part-time'), selected: _employmentType == 'PART_TIME', onSelected: (_) => setState(() => _employmentType = 'PART_TIME')),
                ChoiceChip(label: const Text('Theo ca'), selected: _employmentType == 'SHIFT_BASED', onSelected: (_) => setState(() => _employmentType = 'SHIFT_BASED')),
              ],
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              children: {'MORNING': 'Sáng', 'AFTERNOON': 'Chiều', 'EVENING': 'Tối', 'NIGHT': 'Đêm', 'FLEXIBLE': 'Linh hoạt'}
                  .entries
                  .map((e) => FilterChip(
                        label: Text(e.value),
                        selected: _shifts.contains(e.key),
                        onSelected: (sel) => setState(() => sel ? _shifts.add(e.key) : _shifts.remove(e.key)),
                      ))
                  .toList(),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: TextField(controller: _shiftStartController, decoration: const InputDecoration(labelText: 'Giờ bắt đầu (vd 17:00)', border: OutlineInputBorder()))),
                const SizedBox(width: 12),
                Expanded(child: TextField(controller: _shiftEndController, decoration: const InputDecoration(labelText: 'Giờ kết thúc (vd 22:00)', border: OutlineInputBorder()))),
              ],
            ),
          ],
        ),
      );

  Widget _stepLocation() => _stepWrapper(
        'Địa điểm',
        _locations.isEmpty
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Bạn chưa có cơ sở nào.'),
                  const SizedBox(height: 4),
                  const Text(
                    'Thêm địa chỉ cơ sở để sử dụng cho tin tuyển dụng.',
                    style: TextStyle(color: Colors.black54, fontSize: 12),
                  ),
                  const SizedBox(height: 12),
                  if (_loadingLocations)
                    const Center(child: CircularProgressIndicator())
                  else
                    FilledButton.icon(
                      onPressed: _createLocation,
                      icon: const Icon(Icons.add_business),
                      label: const Text('+ TẠO CƠ SỞ'),
                    ),
                ],
              )
            : Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _locations
                    .map((loc) => ChoiceChip(
                          label: Text(loc['name']),
                          selected: _locationId == loc['id'],
                          onSelected: (_) => setState(() => _locationId = loc['id']),
                        ))
                    .toList(),
              ),
      );

  Widget _stepUrgency() => _stepWrapper(
        'Khi nào cần người?',
        Wrap(
          spacing: 8,
          children: {
            'IMMEDIATE': 'Đi làm ngay',
            'WITHIN_3_DAYS': 'Trong 3 ngày',
            'WITHIN_7_DAYS': 'Trong 7 ngày',
            'NOT_URGENT': 'Không gấp',
          }
              .entries
              .map((e) => ChoiceChip(
                    label: Text(e.value),
                    selected: _startUrgency == e.key,
                    onSelected: (_) => setState(() => _startUrgency = e.key),
                  ))
              .toList(),
        ),
      );

  Widget _stepExperience() => _stepWrapper(
        'Kinh nghiệm',
        Wrap(
          spacing: 8,
          children: {
            'NOT_REQUIRED': 'Không cần kinh nghiệm',
            'PREFERRED': 'Có kinh nghiệm',
            'REQUIRED': 'Bắt buộc kinh nghiệm',
          }
              .entries
              .map((e) => ChoiceChip(
                    label: Text(e.value),
                    selected: _requiredExperience == e.key,
                    onSelected: (_) => setState(() => _requiredExperience = e.key),
                  ))
              .toList(),
        ),
      );

  Widget _stepDescription() => _stepWrapper(
        'Mô tả ngắn',
        TextField(
          controller: _descriptionController,
          maxLines: 5,
          decoration: const InputDecoration(
            hintText: 'Vd: Quán cần 2 phục vụ ca tối, làm từ 17h đến 22h...',
            border: OutlineInputBorder(),
          ),
        ),
      );
}
