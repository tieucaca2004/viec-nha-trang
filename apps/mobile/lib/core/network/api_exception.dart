/// Lỗi gọi API, luôn kèm [userMessage] tiếng Việt dễ hiểu - không bao giờ hiển thị
/// raw stack trace hay message kỹ thuật cho người dùng (đặc tả §26).
class ApiException implements Exception {
  final int statusCode;
  final String rawMessage;

  /// Số giây phải chờ, đọc từ header `Retry-After` khi bị rate limit (429). Backend
  /// (@nestjs/throttler) CÓ gửi header này - dùng nó để báo đúng "chờ N giây" thay vì câu chung
  /// chung "thử lại sau ít phút" khiến người dùng tưởng app hỏng. null nếu server không gửi.
  final int? retryAfterSeconds;

  ApiException(this.statusCode, this.rawMessage, {this.retryAfterSeconds});

  factory ApiException.network() => ApiException(0, 'network');
  factory ApiException.timeout() => ApiException(-1, 'timeout');

  bool get isUnauthorized => statusCode == 401;
  bool get isForbidden => statusCode == 403;
  bool get isNotFound => statusCode == 404;
  bool get isValidation => statusCode == 400;
  bool get isRateLimited => statusCode == 429;
  bool get isNetwork => statusCode == 0;
  bool get isTimeout => statusCode == -1;
  bool get isServerError => statusCode >= 500;

  String get userMessage {
    if (isNetwork) return 'Không thể kết nối. Kiểm tra Internet và thử lại.';
    if (isTimeout) return 'Kết nối quá chậm. Vui lòng thử lại.';
    if (isUnauthorized) return 'Phiên đăng nhập đã hết. Vui lòng đăng nhập lại.';
    if (isForbidden) return 'Bạn không có quyền thực hiện thao tác này.';
    if (isNotFound) return 'Không tìm thấy dữ liệu.';
    if (isRateLimited) {
      final wait = retryAfterSeconds;
      if (wait != null && wait > 0) {
        return 'Bạn đã yêu cầu quá nhiều lần. Vui lòng chờ $wait giây rồi thử lại.';
      }
      return 'Bạn thao tác quá nhanh. Vui lòng thử lại sau ít phút.';
    }
    if (isValidation) return rawMessage.isNotEmpty ? rawMessage : 'Vui lòng kiểm tra thông tin.';
    if (isServerError) return 'Hệ thống đang bận. Vui lòng thử lại sau.';
    return 'Đã có lỗi xảy ra. Vui lòng thử lại.';
  }

  @override
  String toString() => userMessage;
}
