import { ConfigService } from '@nestjs/config';
import { selectSmsProvider } from './sms-provider.factory';
import { ConsoleSmsProvider } from '../common/services/console-sms.provider';
import { EsmsProvider } from '../common/services/esms.provider';

describe('selectSmsProvider (đặc tả: chọn SmsProvider bằng SMS_PROVIDER)', () => {
  const consoleProvider = new ConsoleSmsProvider();
  const esmsProvider = {} as EsmsProvider;

  function configWith(value: string | undefined): ConfigService {
    return { get: () => value } as unknown as ConfigService;
  }

  it('SMS_PROVIDER=console -> trả về ConsoleSmsProvider', () => {
    expect(selectSmsProvider(configWith('console'), consoleProvider, esmsProvider)).toBe(consoleProvider);
  });

  it('SMS_PROVIDER không đặt (undefined) -> mặc định ConsoleSmsProvider', () => {
    expect(selectSmsProvider(configWith(undefined), consoleProvider, esmsProvider)).toBe(consoleProvider);
  });

  it('SMS_PROVIDER=esms -> trả về EsmsProvider', () => {
    expect(selectSmsProvider(configWith('esms'), consoleProvider, esmsProvider)).toBe(esmsProvider);
  });

  it('SMS_PROVIDER=giá trị không hợp lệ -> fail fast với lỗi rõ ràng', () => {
    expect(() => selectSmsProvider(configWith('twilio'), consoleProvider, esmsProvider)).toThrow(
      /SMS_PROVIDER="twilio" không hợp lệ/,
    );
  });
});
