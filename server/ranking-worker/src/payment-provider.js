/**
 * Provider boundary. Implementations authenticate exact raw bytes before returning
 * {eventId, subscriptionRef, orderRef, revision, periodStart, paidThrough,
 *  status, autoRenew, managementURL}. revision is a monotonic subscription integer
 * or null (requiring authoritative reconciliation). status is paid, pending,
 * failed, cancelled, refunded or revoked. Dates are UTC instants; paidThrough is
 * exclusive. managementURL must already be verified by the provider integration.
 */
export class PaymentProvider {
  async verifyWebhook(_rawBytes, _headers) { throw new Error("unavailable"); }
  async getSubscription(_providerRef) { throw new Error("unavailable"); }
}

// TODO(WAFFO_VERIFIED_INTEGRATION): obtain official webhook signature/API docs,
// authenticated sandbox fixtures and ordering semantics, verify renewal/refund,
// cancellation management, verified annual checkout terms and receipt/support recovery
// before enabling payments. The app keeps checkout and management unavailable until then.
export class WaffoPaymentProvider extends PaymentProvider {}
