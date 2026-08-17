import 'package:flutter/material.dart';
import '../../../models/job.dart';

/// Job Card hiển thị đủ trường tối thiểu theo đặc tả mục 6:
/// tên công việc, cơ sở, lương, ca, khu vực + khoảng cách, loại việc,
/// đi làm ngay, xác minh, thời gian đăng.
class JobCard extends StatelessWidget {
  final Job job;
  final VoidCallback onTap;
  final VoidCallback onApply;

  const JobCard({super.key, required this.job, required this.onTap, required this.onApply});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job.title.toUpperCase(),
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                  if (job.isUrgent)
                    const Padding(
                      padding: EdgeInsets.only(left: 6),
                      child: Text('🔥 Tuyển gấp', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                    ),
                ],
              ),
              const SizedBox(height: 2),
              Text(job.employer?.businessName ?? '', style: const TextStyle(color: Colors.black54)),
              const SizedBox(height: 6),
              Text(
                job.salaryLabel,
                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 16),
              ),
              if (job.shiftStartTime != null && job.shiftEndTime != null)
                Text('${job.shiftStartTime}–${job.shiftEndTime}'),
              const SizedBox(height: 6),
              Wrap(
                spacing: 12,
                runSpacing: 4,
                children: [
                  if (job.area != null)
                    Text(
                      '📍 ${job.area!.name}${job.distanceKm != null ? ' · ${job.distanceKm!.toStringAsFixed(1)} km' : ''}',
                    ),
                  Text(job.employmentType == 'FULL_TIME' ? 'Full-time' : 'Part-time'),
                  if (job.startUrgency == 'IMMEDIATE') const Text('Đi làm ngay'),
                  if (job.employer?.isVerified == true) const Text('🟢 Đã xác minh'),
                ],
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: onApply,
                  child: const Text('ỨNG TUYỂN 1 CHẠM'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
