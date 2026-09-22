import '../../../core/network/api_client.dart';

/// Đánh giá sau khi đơn ứng tuyển đạt trạng thái HIRED (đặc tả mục 23).
///
/// MVP chỉ triển khai chiều JOB_SEEKER đánh giá EMPLOYER (đúng scope được giao: CTA đặt ở
/// ApplicationsScreen - màn hình CHỈ dành cho job seeker, xem main_nav_scaffold.dart
/// `_SeekerNavState._loggedInScreens`, không bao giờ hiển thị cho employer). Chiều ngược lại
/// (EMPLOYER đánh giá JOB_SEEKER) không có màn hình nào gọi tới - không tự thêm để tránh mở rộng
/// scope ngoài yêu cầu.
///
/// Contract khớp đúng ReviewsController/CreateReviewDto/Review model hiện có
/// (apps/backend/src/reviews/reviews.module.ts) - không đoán field:
/// - POST /reviews: { reviewerType, applicationId, rating (1-5), comment? } -> Review đầy đủ.
///   employerId/jobSeekerId KHÔNG gửi từ client - backend tự suy ra từ applicationId (Critical #5
///   FULL AUDIT: nhận trực tiếp từ client là lỗ hổng bypass kiểm tra HIRED).
/// - GET /reviews?targetType=employer&targetId=<employerId>: trả về TOÀN BỘ review của employer
///   đó (không lọc theo reviewer) - dùng để xác định 1 applicationId cụ thể đã được đánh giá hay
///   chưa (field `applicationId` có trong mỗi Review trả về), vì backend không có endpoint
///   "review của tôi cho đơn này" riêng và ownership đã được backend đảm bảo lúc tạo (chỉ đúng
///   job seeker của application đó mới tạo được review mang applicationId này).
class ReviewsService {
  final ApiClient api;
  ReviewsService(this.api);

  Future<Map<String, dynamic>> createEmployerReview({
    required String applicationId,
    required int rating,
    String? comment,
  }) async {
    final res = await api.post('/reviews', body: {
      'reviewerType': 'JOB_SEEKER',
      'applicationId': applicationId,
      'rating': rating,
      if (comment != null && comment.trim().isNotEmpty) 'comment': comment.trim(),
    });
    return res as Map<String, dynamic>;
  }

  Future<List<dynamic>> listForEmployer(String employerId) async {
    final res = await api.get('/reviews', query: {'targetType': 'employer', 'targetId': employerId});
    return res as List;
  }
}
