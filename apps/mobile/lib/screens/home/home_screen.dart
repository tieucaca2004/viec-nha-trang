import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:provider/provider.dart';
import '../../core/api_client.dart';
import '../../models/job.dart';
import '../../services/applications_service.dart';
import '../../services/jobs_service.dart';
import '../job_detail/job_detail_screen.dart';
import 'widgets/job_card.dart';

/// Trang chủ - màn hình quan trọng nhất (đặc tả mục 6).
/// Mục tiêu: mở app -> chọn nhu cầu -> thấy việc phù hợp trong ~10 giây.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _searchController = TextEditingController();
  final _filters = JobFilters();
  List<Job> _jobs = [];
  bool _loading = true;
  String? _error;
  String? _activeQuickFilter;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final jobsService = context.read<JobsService>();
      final jobs = await jobsService.search(_filters);
      setState(() => _jobs = jobs);
    } on ApiException catch (e) {
      setState(() => _error = e.message);
    } finally {
      setState(() => _loading = false);
    }
  }

  Future<void> _useMyLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      var granted = permission;
      if (permission == LocationPermission.denied) {
        granted = await Geolocator.requestPermission();
      }
      if (granted == LocationPermission.denied || granted == LocationPermission.deniedForever) return;
      final position = await Geolocator.getCurrentPosition();
      _filters.latitude = position.latitude;
      _filters.longitude = position.longitude;
      _filters.radiusKm = 5;
      _filters.sortBy = 'distance';
      await _load();
    } catch (_) {
      // Vị trí không khả dụng - bỏ qua, dùng danh sách theo thời gian đăng.
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

  Future<void> _apply(Job job) async {
    try {
      await context.read<ApplicationsService>().apply(job.id);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Ứng tuyển thành công.')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('📍 NHA TRANG'),
        automaticallyImplyLeading: false,
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
                onSubmitted: (value) {
                  _filters.keyword = value.trim().isEmpty ? null : value.trim();
                  _load();
                },
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text(_error!));
    if (_jobs.isEmpty) return const Center(child: Text('Chưa có việc phù hợp. Thử đổi bộ lọc nhé.'));
    return ListView.builder(
      itemCount: _jobs.length,
      itemBuilder: (context, index) {
        final job = _jobs[index];
        return JobCard(
          job: job,
          onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: job.id))),
          onApply: () => _apply(job),
        );
      },
    );
  }
}
