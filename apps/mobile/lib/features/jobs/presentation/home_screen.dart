import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../../core/auth/session.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/job.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../../shared/widgets/auth_prompt.dart';
import '../../applications/data/applications_service.dart';
import '../../saved_jobs/data/saved_jobs_service.dart';
import '../data/jobs_service.dart';
import 'job_detail_screen.dart';
import 'widgets/job_card.dart';
import 'widgets/job_filter_sheet.dart';

/// Trang chủ - màn hình quan trọng nhất (đặc tả §7 Phase 3).
/// Mục tiêu: mở app -> chọn nhu cầu -> thấy việc phù hợp trong ~10 giây.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _filters = JobFilters();
  Timer? _debounce;

  List<Job> _jobs = [];
  int _total = 0;
  bool _loading = true;
  bool _loadingMore = false;
  ApiException? _error;
  String? _activeQuickFilter;
  Set<String> _appliedJobIds = {};
  Set<String> _savedJobIds = {};
  List<JobCategory> _categories = [];
  List<Area> _areas = [];
  // Chốt chống double-tap cho nút lưu trên JobCard - khác với JobDetailScreen (_togglingSave) hay
  // SavedJobsScreen (tự an toàn nhờ xoá khỏi list ngay lập tức trước khi await), nút lưu ở đây
  // không có gì ngăn 2 lần bấm gần nhau đều lọt qua trong lúc request đầu còn đang treo.
  final Set<String> _togglingSaveJobIds = {};

  static const _pageSize = 20;

  @override
  void initState() {
    super.initState();
    _loadFilterOptions();
    _loadAppliedIds();
    _loadSavedIds();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // Cùng lớp lỗi đã sửa ở PostJobWizardScreen/JobSeekerProfileFormScreen: trước đây categories
  // và areas được await TUẦN TỰ trong 1 try/catch, nên chỉ cần areas() lỗi là categories đã tải
  // được cũng bị vứt đi - bộ lọc trang chủ mất luôn cả 2 dropdown dù 1 trong 2 API vẫn hoạt động
  // bình thường. Chạy song song, giữ lại phần nào tải được.
  Future<void> _loadFilterOptions() async {
    final jobsService = context.read<JobsService>();
    final results = await Future.wait<Object?>([
      _safeCall(jobsService.categories()),
      _safeCall(jobsService.areas()),
    ]);
    if (!mounted) return;
    final categoriesResult = results[0];
    final areasResult = results[1];
    setState(() {
      // Bộ lọc không tải được không nên chặn trang chủ hiển thị job - bỏ qua lặng lẽ,
      // filter sheet sẽ chỉ thiếu tuỳ chọn cho tới lần thử lại kế tiếp.
      if (categoriesResult is List<JobCategory>) _categories = categoriesResult;
      if (areasResult is List<Area>) _areas = areasResult;
    });
  }

  Future<Object?> _safeCall(Future<Object?> future) async {
    try {
      return await future;
    } on ApiException catch (e) {
      return e;
    }
  }

  Future<void> _loadAppliedIds() async {
    // Khách (chưa đăng nhập) không có gì để tải - gọi /applications/me sẽ chỉ tốn 1 request 401
    // vô ích (đặc tả AUTH UX Part 11: guest browsing không phụ thuộc bất kỳ API cần đăng nhập nào).
    if (!context.read<Session>().isLoggedIn) return;
    try {
      final applications = await context.read<ApplicationsService>().listMine();
      if (!mounted) return;
      setState(() => _appliedJobIds = applications.map((a) => a.job?.id).whereType<String>().toSet());
    } catch (_) {
      // Không chặn trang chủ nếu không tải được danh sách đã ứng tuyển.
    }
  }

  Future<void> _loadSavedIds() async {
    if (!context.read<Session>().isLoggedIn) return;
    try {
      final saved = await context.read<SavedJobsService>().listSaved();
      if (!mounted) return;
      setState(() => _savedJobIds = saved.map((s) => (s as Map)['jobId']?.toString()).whereType<String>().toSet());
    } catch (_) {
      // Không chặn trang chủ nếu không tải được danh sách đã lưu - nút lưu vẫn hoạt động,
      // chỉ là trạng thái hiển thị ban đầu có thể chưa chính xác cho tới lần tải lại kế tiếp.
    }
  }

  // Đặc tả AUTH UX Part 3/6: khách bấm Lưu -> hỏi xác thực (KHÔNG âm thầm lưu lạc quan rồi lỗi
  // 401 mới báo) -> xác thực xong tự tiếp tục lưu đúng job này, không cần bấm lại.
  Future<void> _toggleSave(Job job) async {
    // Bug thật: không có gì chặn 2 lần bấm gần nhau trong lúc request đầu còn đang treo (khác
    // JobDetailScreen._toggleSave() đã có _togglingSave, hay SavedJobsScreen._unsave() tự an
    // toàn nhờ xoá khỏi list trước khi await) - dẫn tới 2 request POST/DELETE /saved-jobs.
    if (_togglingSaveJobIds.contains(job.id)) return;
    setState(() => _togglingSaveJobIds.add(job.id));
    final wasSaved = _savedJobIds.contains(job.id);
    try {
      final saved = await runWithAuth<bool>(
        context,
        reason: 'Để lưu việc này, bạn cần đăng nhập hoặc tạo tài khoản.',
        action: () async {
          final savedJobsService = context.read<SavedJobsService>();
          if (wasSaved) {
            await savedJobsService.unsave(job.id);
          } else {
            await savedJobsService.save(job.id);
          }
          return !wasSaved;
        },
      );
      if (saved == null || !mounted) return;
      setState(() {
        _savedJobIds = saved ? {..._savedJobIds, job.id} : ({..._savedJobIds}..remove(job.id));
      });
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
    } finally {
      if (mounted) setState(() => _togglingSaveJobIds.remove(job.id));
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jobsService = context.read<JobsService>();
      final result = await jobsService.search(_filters, limit: _pageSize, offset: 0);
      if (!mounted) return;
      setState(() {
        _jobs = result.jobs;
        _total = result.total;
      });
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _loadMore() async {
    if (_loadingMore || _jobs.length >= _total) return;
    setState(() => _loadingMore = true);
    try {
      final jobsService = context.read<JobsService>();
      final result = await jobsService.search(_filters, limit: _pageSize, offset: _jobs.length);
      if (!mounted) return;
      setState(() => _jobs = [..._jobs, ...result.jobs]);
    } catch (_) {
      // Lỗi khi tải thêm không cần chặn danh sách đã có - user có thể kéo lại để thử tiếp.
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 400), () {
      _filters.keyword = value.trim().isEmpty ? null : value.trim();
      _load();
    });
  }

  Future<void> _useMyLocation() async {
    try {
      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied || permission == LocationPermission.deniedForever) {
        // Không block app nếu user từ chối GPS (đặc tả §22) - giữ nguyên danh sách theo mặc định.
        return;
      }
      final position = await Geolocator.getCurrentPosition();
      _filters.latitude = position.latitude;
      _filters.longitude = position.longitude;
      _filters.radiusKm = 5;
      _filters.sortBy = 'distance';
      await _load();
    } catch (_) {
      // Vị trí không khả dụng (GPS tắt, timeout...) - bỏ qua, dùng danh sách theo thời gian đăng.
    }
  }

  void _toggleQuickFilter(String key) {
    setState(() {
      if (_activeQuickFilter == key) {
        _activeQuickFilter = null;
        _filters.isUrgent = null;
        _filters.employmentType = null;
        _filters.sortBy = null;
      } else {
        _activeQuickFilter = key;
        _filters.isUrgent = key == 'urgent' ? true : null;
        _filters.employmentType = key == 'part_time'
            ? 'PART_TIME'
            : key == 'full_time'
                ? 'FULL_TIME'
                : null;
        _filters.sortBy = key == 'newest'
            ? 'newest'
            : key == 'salary'
                ? 'salary'
                : key == 'near_me'
                    ? 'distance'
                    : null;
      }
    });
    if (key == 'near_me' && _activeQuickFilter == 'near_me') {
      _useMyLocation();
    } else {
      _load();
    }
  }

  Future<void> _openFilterSheet() async {
    final result = await JobFilterSheet.show(context, initial: _filters, categories: _categories, areas: _areas);
    if (result == null) return;
    setState(() {
      _filters.categoryId = result.categoryId;
      _filters.areaId = result.areaId;
      _filters.radiusKm = result.radiusKm;
      _filters.employmentType = result.employmentType;
      _filters.shift = result.shift;
      _filters.startUrgency = result.startUrgency;
      _filters.salaryMin = result.salaryMin;
      _filters.salaryMax = result.salaryMax;
      _activeQuickFilter = null;
    });
    await _load();
  }

  Future<void> _apply(Job job) async {
    try {
      final applied = await runWithAuth<bool>(
        context,
        reason: 'Để ứng tuyển, bạn cần đăng nhập hoặc tạo tài khoản.',
        action: () async {
          await context.read<ApplicationsService>().apply(job.id);
          return true;
        },
      );
      if (applied != true || !mounted) return;
      setState(() => _appliedJobIds = {..._appliedJobIds, job.id});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ứng tuyển thành công.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📍 NHA TRANG'),
        automaticallyImplyLeading: false,
        actions: [
          IconButton(icon: const Icon(Icons.tune), onPressed: _openFilterSheet, tooltip: 'Bộ lọc'),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: 'Bạn muốn tìm việc gì?',
                  prefixIcon: const Icon(Icons.search),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
                onChanged: _onSearchChanged,
              ),
            ),
            SizedBox(
              height: 40,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: [
                  _quickFilterChip('near_me', 'Gần tôi'),
                  _quickFilterChip('newest', 'Việc mới'),
                  _quickFilterChip('urgent', 'Đi làm ngay'),
                  _quickFilterChip('part_time', 'Part-time'),
                  _quickFilterChip('full_time', 'Full-time'),
                  _quickFilterChip('salary', 'Lương cao'),
                ],
              ),
            ),
            const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('VIỆC PHÙ HỢP VỚI BẠN', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ),
            Expanded(child: _buildList()),
          ],
        ),
      ),
    );
  }

  Widget _quickFilterChip(String key, String label) {
    final selected = _activeQuickFilter == key;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 4),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => _toggleQuickFilter(key),
      ),
    );
  }

  Widget _buildList() {
    return AsyncStateView<List<Job>>(
      loading: _loading,
      error: _error,
      data: _loading ? null : _jobs,
      isEmpty: (jobs) => jobs.isEmpty,
      emptyMessage: 'Chưa có việc phù hợp. Thử đổi bộ lọc nhé.',
      onRetry: _load,
      builder: (context, jobs) => NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.metrics.pixels >= notification.metrics.maxScrollExtent - 200) {
            _loadMore();
          }
          return false;
        },
        child: ListView.builder(
          itemCount: jobs.length + (_loadingMore ? 1 : 0),
          itemBuilder: (context, index) {
            if (index >= jobs.length) {
              return const Padding(
                padding: EdgeInsets.all(16),
                child: Center(child: CircularProgressIndicator()),
              );
            }
            final job = jobs[index];
            return JobCard(
              job: job,
              isApplied: _appliedJobIds.contains(job.id),
              isSaved: _savedJobIds.contains(job.id),
              onTap: () => Navigator.of(context)
                  .push(MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: job.id)))
                  .then((_) {
                _loadAppliedIds();
                _loadSavedIds();
              }),
              onApply: () => _apply(job),
              onToggleSave: _togglingSaveJobIds.contains(job.id) ? null : () => _toggleSave(job),
            );
          },
        ),
      ),
    );
  }
}
