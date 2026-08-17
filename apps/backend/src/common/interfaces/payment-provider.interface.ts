// Interface trung lập để sau này cắm VNPay/MoMo/ZaloPay/Apple-Google IAP
// mà không phải đổi schema hay các module gọi thanh toán (đặc tả mục 28).
export interface CreatePaymentResult {
  paymentUrlOrToken: string;
  providerTxnId: string;
}

export interface PaymentProvider {
  createPayment(params: { subscriptionId: string; amountVnd: number }): Promise<CreatePaymentResult>;
  verifyWebhook(payload: unknown, signature: string): Promise<{ providerTxnId: string; success: boolean }>;
}
