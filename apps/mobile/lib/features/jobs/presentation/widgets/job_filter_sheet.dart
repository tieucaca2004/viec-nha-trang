import 'package:flutter/material.dart';
import '../../../../shared/models/job.dart';
import '../../../../shared/utils/normalize_vi.dart';
import '../../data/jobs_service.dart';

/// Bottom sheet lọc việc làm (đặc tả §10 Phase 3): khoảng cách, khu vực, danh mục, lương,
/// loại việc, ca, thời gian bắt đầu. Có ÁP DỤNG / XÓA BỘ LỌC.
class JobFilterSheet extends StatefulWidget {
  final JobFilters initial;
  final List<JobCategory> categories;
  final List<Area> areas;

  const JobFilterSheet({super.key, required this.initial, required this.categories, required this.areas});

  static Future<JobFilters?> show(
    BuildContext context, {
    required JobFilters initial,
    required List<JobCategory> categories,
    required List<Area> areas,
  }) {
    return showModalBottomSheet<JobFilters>(
      context: context,
      isScrollControlled: true,
      builder: (_) => JobFilterSheet(initial: initial, categories: categories, areas: areas),
    );
  }

  @override
  State<JobFilterSheet> createState() => _JobFilterSheetState();
}

class _JobFilterSheetState extends State<JobFilterSheet> {
  late JobFilters _filters;
  double? _radiusKm;
  late final TextEditingController _salaryMinController;
  late final TextEditingController _salaryMaxController;
  final _areaSearchController = TextEditingController();
  String _areaSearchQuery = '';

  @override
  void initState() {
    super.initState();
    _filters = widget.initial.copy();
    _radiusKm = _filters.radiusKm;
    _salaryMinController = TextEditingController(text: _filters.salaryMin?.toString() ?? '');
    _salaryMaxController = TextEditingController(text: _filters.salaryMax?.toString() ?? '');
  }

  @override
  void dispose() {
    _salaryMinController.dispose();
    _salaryMaxController.dispose();
    _areaSearchController.dispose();
    super.dispose();
  }

  // Danh sách Area cũ (Vĩnh Hải, Lộc Thọ, ...) đã tải sẵn từ widget.areas - search client-side,
  // không phân biệt dấu/hoa-thường, không cần gọi API riêng vì danh sách đã có đủ trong bộ nhớ.
  List<Area> get _filteredAreas {
    if (_areaSearchQuery.trim().isEmpty) return widget.areas;
    final normalizedQuery = normalizeVietnamese(_areaSearchQuery);
    return widget.areas.where((a) => normalizeVietnamese(a.name).contains(normalizedQuery)).toList();
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Bộ lọc', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  children: [
                    _sectionTitle('Khoảng cách'),
                    // Bổ sung 20/30 km (Phase F §5/§10) - cùng field _radiusKm/API radiusKm hiện
                    // có, chỉ thêm lựa chọn lớn hơn, không đổi hành vi. "Toàn Khánh Hòa" CHƯA
                    // thêm ở đây: cần dataset khu vực toàn tỉnh đã xác minh nguồn trước (đang chờ
                    // duyệt), không giả lập bằng radius cực lớn theo đúng yêu cầu.
                    if (_radiusKm != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Text(
                          'Trong bán kính ${_radiusKm!.toInt()} km tính theo khoảng cách thực tế, không theo ranh giới hành chính.',
                          style: const TextStyle(color: Colors.black54, fontSize: 12),
                        ),
                      ),
                    Wrap(
                      spacing: 8,
                      children: [1.0, 3.0, 5.0, 10.0, 20.0, 30.0]
                          .map((km) => ChoiceChip(
                                label: Text('${km.toInt()} km'),
                                selected: _radiusKm == km,
                                onSelected: (_) => setState(() => _radiusKm = (_radiusKm == km) ? null : km),
                              ))
                          .toList(),
                    ),
                    _sectionTitle('Khu vực'),
                    if (widget.areas.length > 6) ...[
                      TextField(
                        controller: _areaSearchController,
                        decoration: const InputDecoration(
                          hintText: 'Tìm phường/xã (vd: Vĩnh Hải, Lộc Thọ)',
                          prefixIcon: Icon(Icons.search),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: (v) => setState(() => _areaSearchQuery = v),
                      ),
                      const SizedBox(height: 8),
                    ],
                    if (_filteredAreas.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 8),
                        child: Text('Không tìm thấy khu vực phù hợp.', style: TextStyle(color: Colors.black54)),
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _filteredAreas
                            .map((a) => ChoiceChip(
                                  label: Text(a.name),
                                  selected: _filters.areaId == a.id,
                                  onSelected: (_) => setState(() => _filters.areaId = (_filters.areaId == a.id) ? null : a.id),
                                ))
                            .toList(),
                      ),
                    _sectionTitle('Danh mục'),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: widget.categories
                          .map((c) => ChoiceChip(
                                label: Text(c.name),
                                selected: _filters.categoryId == c.id,
                                onSelected: (_) => setState(() => _filters.categoryId = (_filters.categoryId == c.id) ? null : c.id),
                              ))
                          .toList(),
                    ),
                    _sectionTitle('Lương (đ)'),
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: _salaryMinController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Từ', border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: TextField(
                            controller: _salaryMaxController,
                            keyboardType: TextInputType.number,
                            decoration: const InputDecoration(labelText: 'Đến', border: OutlineInputBorder(), isDense: true),
                          ),
                        ),
                      ],
                    ),
                    _sectionTitle('Loại việc'),
                    Wrap(
                      spacing: 8,
                      children: {'FULL_TIME': 'Full-time', 'PART_TIME': 'Part-time', 'SHIFT_BASED': 'Theo ca', 'SEASONAL': 'Thời vụ'}
                          .entries
                          .map((e) => ChoiceChip(
                                label: Text(e.value),
                                selected: _filters.employmentType == e.key,
                                onSelected: (_) => setState(() => _filters.employmentType = (_filters.employmentType == e.key) ? null : e.key),
                              ))
                          .toList(),
                    ),
                    _sectionTitle('Ca làm'),
                    Wrap(
                      spacing: 8,
                      children: {'MORNING': 'Sáng', 'AFTERNOON': 'Chiều', 'EVENING': 'Tối', 'NIGHT': 'Đêm', 'FLEXIBLE': 'Linh hoạt'}
                          .entries
                          .map((e) => ChoiceChip(
                                label: Text(e.value),
                                selected: _filters.shift == e.key,
                                onSelected: (_) => setState(() => _filters.shift = (_filters.shift == e.key) ? null : e.key),
                              ))
                          .toList(),
                    ),
                    _sectionTitle('Khi nào cần người'),
                    Wrap(
                      spacing: 8,
                      children: {'IMMEDIATE': 'Đi làm ngay', 'WITHIN_3_DAYS': 'Trong 3 ngày', 'WITHIN_7_DAYS': 'Trong 7 ngày'}
                          .entries
                          .map((e) => ChoiceChip(
                                label: Text(e.value),
                                selected: _filters.startUrgency == e.key,
                                onSelected: (_) => setState(() => _filters.startUrgency = (_filters.startUrgency == e.key) ? null : e.key),
                              ))
                          .toList(),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(JobFilters()),
                      child: const Text('XÓA BỘ LỌC'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        _filters.radiusKm = _radiusKm;
                        _filters.salaryMin = int.tryParse(_salaryMinController.text.trim());
                        _filters.salaryMax = int.tryParse(_salaryMaxController.text.trim());
                        Navigator.of(context).pop(_filters);
                      },
                      child: const Text('ÁP DỤNG'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _sectionTitle(String text) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      );
}
