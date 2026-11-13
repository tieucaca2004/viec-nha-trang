import { ArgumentsHost, Catch, HttpStatus } from '@nestjs/common';
import { BaseExceptionFilter } from '@nestjs/core';
import { Prisma } from '@prisma/client';

// Lỗi Prisma "đã biết" là lỗi của request (trùng unique, tham chiếu không tồn tại, không tìm thấy
// bản ghi, dữ liệu sai kiểu), không phải lỗi server - trả đúng 4xx thay vì để rơi thành 500.
// Mọi lỗi Prisma khác vẫn đi qua BaseExceptionFilter như cũ (500).
const KNOWN_ERRORS: Record<string, { status: HttpStatus; error: string; message: string }> = {
  P2002: { status: HttpStatus.CONFLICT, error: 'Conflict', message: 'Dữ liệu đã tồn tại.' },
  P2003: { status: HttpStatus.NOT_FOUND, error: 'Not Found', message: 'Dữ liệu liên quan không tồn tại.' },
  P2025: { status: HttpStatus.NOT_FOUND, error: 'Not Found', message: 'Không tìm thấy dữ liệu.' },
};

@Catch(Prisma.PrismaClientKnownRequestError, Prisma.PrismaClientValidationError)
export class PrismaExceptionFilter extends BaseExceptionFilter {
  catch(exception: Prisma.PrismaClientKnownRequestError | Prisma.PrismaClientValidationError, host: ArgumentsHost) {
    const mapped =
      exception instanceof Prisma.PrismaClientValidationError
        ? { status: HttpStatus.BAD_REQUEST, error: 'Bad Request', message: 'Dữ liệu không hợp lệ.' }
        : KNOWN_ERRORS[exception.code];
    if (!mapped || host.getType() !== 'http') {
      return super.catch(exception, host);
    }
    const response = host.switchToHttp().getResponse();
    response.status(mapped.status).json({ statusCode: mapped.status, message: mapped.message, error: mapped.error });
  }
}
