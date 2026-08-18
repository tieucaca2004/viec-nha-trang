import { ConfigService } from '@nestjs/config';
import { ServiceUnavailableException } from '@nestjs/common';
import { EsmsProvider } from './esms.provider';

describe('EsmsProvider (đặc tả: gửi OTP thật qua eSMS.vn, xử lý lỗi an toàn)', () => {
  let provider: EsmsProvider;
  let fetchSpy: jest.SpyInstance;

  function configWith(values: Record<string, string>): ConfigService {
    return { get: (key: string) => values[key] } as unknown as ConfigService;
  }

  beforeEach(() => {
    provider = new EsmsProvider(
      configWith({ ESMS_API_KEY: 'test-key', ESMS_SECRET_KEY: 'test-secret', ESMS_BRANDNAME: '' }),
    );
    fetchSpy = jest.spyOn(global, 'fetch');
  });

  afterEach(() => {
    fetchSpy.mockRestore();
  });

  it('gửi thành công khi eSMS trả CodeResult=100', async () => {
    fetchSpy.mockResolvedValue({
      ok: true,
      json: async () => ({ CodeResult: '100', SMSID: '123' }),
    } as Response);

    await expect(provider.sendOtp('0900000001', '123456')).resolves.toBeUndefined();

    const calledUrl = fetchSpy.mock.calls[0][0] as string;
    expect(calledUrl).toContain('rest.esms.vn');
    expect(calledUrl).toContain('Phone=0900000001');
    // Không bao giờ log/lộ mã OTP hay secret qua URL bị log ra ngoài test - chỉ xác nhận nó được
    // gửi đúng field cho eSMS, không kiểm tra log console.
    expect(calledUrl).toContain('ApiKey=test-key');
  });

  it('chấp nhận cả field CodeResponse (một số phiên bản eSMS dùng tên khác CodeResult)', async () => {
    fetchSpy.mockResolvedValue({
      ok: true,
      json: async () => ({ CodeResponse: '100' }),
    } as Response);

    await expect(provider.sendOtp('0900000001', '123456')).resolves.toBeUndefined();
  });

  it('ném ServiceUnavailableException khi eSMS trả mã lỗi (vd 101 - sai ApiKey/SecretKey)', async () => {
    fetchSpy.mockResolvedValue({
      ok: true,
      json: async () => ({ CodeResult: '101' }),
    } as Response);

    await expect(provider.sendOtp('0900000001', '123456')).rejects.toThrow(ServiceUnavailableException);
  });

  it('ném ServiceUnavailableException khi HTTP status không phải 2xx', async () => {
    fetchSpy.mockResolvedValue({ ok: false, status: 500 } as Response);

    await expect(provider.sendOtp('0900000001', '123456')).rejects.toThrow(ServiceUnavailableException);
  });

  it('ném ServiceUnavailableException khi response không phải JSON hợp lệ', async () => {
    fetchSpy.mockResolvedValue({
      ok: true,
      json: async () => {
        throw new Error('invalid json');
      },
    } as unknown as Response);

    await expect(provider.sendOtp('0900000001', '123456')).rejects.toThrow(ServiceUnavailableException);
  });

  it('ném ServiceUnavailableException khi response thiếu cả CodeResult và CodeResponse', async () => {
    fetchSpy.mockResolvedValue({
      ok: true,
      json: async () => ({ SMSID: '123' }),
    } as Response);

    await expect(provider.sendOtp('0900000001', '123456')).rejects.toThrow(ServiceUnavailableException);
  });

  it('ném ServiceUnavailableException khi có lỗi mạng (fetch reject)', async () => {
    fetchSpy.mockRejectedValue(new TypeError('fetch failed'));

    await expect(provider.sendOtp('0900000001', '123456')).rejects.toThrow(ServiceUnavailableException);
  });

  it('ném ServiceUnavailableException khi timeout (AbortError)', async () => {
    const abortError = new Error('The operation was aborted');
    abortError.name = 'AbortError';
    fetchSpy.mockRejectedValue(abortError);

    await expect(provider.sendOtp('0900000001', '123456')).rejects.toThrow(ServiceUnavailableException);
  });
});
