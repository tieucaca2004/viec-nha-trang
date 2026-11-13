import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/network/api_exception.dart';
import '../../../shared/models/application.dart';
import '../../../shared/widgets/async_state_view.dart';
import '../../jobs/presentation/job_detail_screen.dart';
import '../../reviews/data/reviews_service.dart';
import '../data/applications_service.dart';

/// Theo dõi trạng thái ứng tuyển (đặc tả §13 Phase 3) - tab theo trạng thái.
class ApplicationsScreen extends StatefulWidget {
  const ApplicationsScreen({super.key});

  @override
  State<ApplicationsScreen> createState() => _ApplicationsScreenState();
}

class _Tab {
  final String label;
  final Set<String> statuses;
  const _Tab(this.label, this.statuses);
}

class _ApplicationsScreenState extends State<ApplicationsScreen> with SingleTickerProviderStateMixin {
  static const _tabs = [
    _Tab('Mới', {'NEW'}),
    _Tab('Đã xem', {'VIEWED'}),
    _Tab('Đã liên hệ', {'CONTACTED'}),
    _Tab('Phỏng vấn', {'INTERVIEW'}),
    _Tab('Đã nhận', {'HIRED'}),
    _Tab('Không phù hợp', {'NOT_SUITABLE', 'NO_SHOW'}),
  ];

  late final TabController _tabController;
  List<JobApplication> _applications = [];
  ApiException? _error;
  bool _loading = true;

  // Đánh giá employer sau khi HIRED (đặc tả mục 23). Backend không có endpoint "review của tôi
  // cho đơn này" riêng - _reviewedApplicationIds được suy ra từ GET /reviews?targetType=employer
  // (xem _loadReviewedStatus). _submittingReviewIds chặn double-submit cùng pattern với
  // _togglingSaveJobIds ở HomeScreen/_applyInFlight ở JobDetailScreen.
  Set<String> _reviewedApplicationIds = {};
  final Set<String> _submittingReviewIds = {};
  // POST đã thành công trong phiên này - luôn được gộp vào khi GET /reviews trả về, để response
  // GET chụp trước lúc POST ghi xong không làm CTA "ĐÁNH GIÁ" hiện lại.
  final Set<String> _submittedReviewIds = {};

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: _tabs.length, vsync: this);
    _load();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final apps = await context.read<ApplicationsService>().listMine();
      if (!mounted) return;
      setState(() => _applications = apps);
      unawaited(_loadReviewedStatus(apps));
    } on ApiException catch (e) {
      if (mounted) setState(() => _error = e);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // Không chặn danh sách ứng tuyển nếu bước này lỗi/chậm - xấu nhất là CTA "ĐÁNH GIÁ" hiện ra dù
  // đơn đó đã được đánh giá trước đó (không phải mất dữ liệu, không phải crash).
  Future<void> _loadReviewedStatus(List<JobApplication> apps) async {
    final hiredEmployerIds = apps
        .where((a) => a.status == 'HIRED' && a.job?.employer?.id != null)
        .map((a) => a.job!.employer!.id)
        .toSet();
    if (hiredEmployerIds.isEmpty) return;
    final reviewsService = context.read<ReviewsService>();
    final reviewedIds = <String>{};
    for (final employerId in hiredEmployerIds) {
      try {
        final reviews = await reviewsService.listForEmployer(employerId);
        for (final r in reviews) {
          final review = r as Map;
          // Backend gán employerId cho cả review do EMPLOYER viết về ứng viên, nên GET theo
          // employer trả về cả 2 chiều - chỉ review JOB_SEEKER mới là "ứng viên đã đánh giá".
          if (review['reviewerType'] != 'JOB_SEEKER') continue;
          final appId = review['applicationId'];
          if (appId != null) reviewedIds.add(appId.toString());
        }
      } catch (_) {
        // Bỏ qua lỗi của riêng 1 employer - không chặn các employer khác đã tải được.
      }
    }
    if (mounted) setState(() => _reviewedApplicationIds = {...reviewedIds, ..._submittedReviewIds});
  }

  Future<void> _openReviewDialog(JobApplication app) async {
    if (_submittingReviewIds.contains(app.id)) return;
    final input = await showDialog<_ReviewInput>(
      context: context,
      builder: (_) => _ReviewDialog(businessName: app.job?.employer?.businessName ?? 'nhà tuyển dụng'),
    );
    if (input == null || !mounted) return;
    await _submitReview(app, input);
  }

  Future<void> _submitReview(JobApplication app, _ReviewInput input) async {
    if (_submittingReviewIds.contains(app.id)) return;
    setState(() => _submittingReviewIds.add(app.id));
    try {
      await context.read<ReviewsService>().createEmployerReview(
            applicationId: app.id,
            rating: input.rating,
            comment: input.comment,
          );
      _submittedReviewIds.add(app.id);
      if (!mounted) return;
      setState(() => _reviewedApplicationIds = {..._reviewedApplicationIds, app.id});
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Đã gửi đánh giá. Cảm ơn bạn!')));
    } on ApiException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.userMessage)));
    } finally {
      if (mounted) setState(() => _submittingReviewIds.remove(app.id));
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'HIRED':
        return Colors.green;
      case 'NOT_SUITABLE':
      case 'NO_SHOW':
        return Colors.red;
      case 'INTERVIEW':
        return Colors.orange;
      default:
        return Colors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Ứng tuyển của tôi'),
        automaticallyImplyLeading: false,
        bottom: TabBar(controller: _tabController, isScrollable: true, tabs: _tabs.map((t) => Tab(text: t.label)).toList()),
      ),
      body: AsyncStateView<List<JobApplication>>(
        loading: _loading,
        error: _error,
        data: _loading ? null : _applications,
        onRetry: _load,
        builder: (context, applications) => TabBarView(
          controller: _tabController,
          children: _tabs.map((tab) {
            final items = applications.where((a) => tab.statuses.contains(a.status)).toList();
            if (items.isEmpty) {
              return Center(child: Text('Chưa có đơn ứng tuyển ở trạng thái "${tab.label}".'));
            }
            return RefreshIndicator(
              onRefresh: _load,
              child: ListView.builder(
                itemCount: items.length,
                itemBuilder: (context, index) {
                  final app = items[index];
                  final reviewCta = _buildReviewCta(app);
                  return ListTile(
                    title: Text(app.job?.title ?? ''),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(app.job?.employer?.businessName ?? ''),
                        if (reviewCta != null) reviewCta,
                      ],
                    ),
                    trailing: Chip(
                      label: Text(app.statusLabel, style: const TextStyle(color: Colors.white)),
                      backgroundColor: _statusColor(app.status),
                    ),
                    onTap: app.job == null
                        ? null
                        : () => Navigator.of(context)
                            .push(MaterialPageRoute(builder: (_) => JobDetailScreen(jobId: app.job!.id))),
                  );
                },
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  // CTA đánh giá employer, chỉ hiện khi HIRED và biết employerId (đặc tả mục 23). Không hiện gì
  // nếu chưa HIRED hoặc thiếu employerId trong dữ liệu application (không đoán/hardcode).
  Widget? _buildReviewCta(JobApplication app) {
    if (app.status != 'HIRED' || app.job?.employer?.id == null) return null;
    if (_reviewedApplicationIds.contains(app.id)) {
      return const Padding(
        padding: EdgeInsets.only(top: 4),
        child: Text('Đã đánh giá', style: TextStyle(color: Colors.green, fontSize: 12)),
      );
    }
    final submitting = _submittingReviewIds.contains(app.id);
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: OutlinedButton(
          onPressed: submitting ? null : () => _openReviewDialog(app),
          child: submitting
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('ĐÁNH GIÁ'),
        ),
      ),
    );
  }
}

class _ReviewInput {
  final int rating;
  final String? comment;
  const _ReviewInput(this.rating, this.comment);
}

class _ReviewDialog extends StatefulWidget {
  final String businessName;
  const _ReviewDialog({required this.businessName});

  @override
  State<_ReviewDialog> createState() => _ReviewDialogState();
}

class _ReviewDialogState extends State<_ReviewDialog> {
  int _rating = 0;
  final _commentController = TextEditingController();

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text('Đánh giá ${widget.businessName}'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starIndex = i + 1;
              return IconButton(
                icon: Icon(
                  starIndex <= _rating ? Icons.star : Icons.star_border,
                  color: Colors.amber,
                ),
                onPressed: () => setState(() => _rating = starIndex),
              );
            }),
          ),
          TextField(
            controller: _commentController,
            decoration: const InputDecoration(hintText: 'Nhận xét (không bắt buộc)'),
            maxLines: 3,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('HUỶ'),
        ),
        TextButton(
          onPressed: _rating == 0
              ? null
              : () => Navigator.of(context).pop(_ReviewInput(_rating, _commentController.text)),
          child: const Text('GỬI'),
        ),
      ],
    );
  }
}
