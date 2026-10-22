export class FakePaymentProvider {
  constructor() { this.orders = new Map(); this.events = new Map(); this.subscriptions = new Map(); this.available = true; }
  async verifyWebhook(bytes) {
    if (!this.available) throw new Error("unavailable");
    const event = this.events.get(new TextDecoder().decode(bytes));
    if (!event) throw new Error("unverified");
    return event;
  }
  async getSubscription(ref) {
    if (!this.available || !this.subscriptions.has(ref)) throw new Error("unavailable");
    return this.subscriptions.get(ref);
  }
  async getOrder(ref) {
    if (!this.available || !this.orders.has(ref)) throw new Error("unavailable");
    return this.orders.get(ref);
  }
  add(event) {
    this.events.set(event.eventId, event);
    if (event.product === "one_time_annual") this.orders.set(event.orderRef, event);
    else this.subscriptions.set(event.subscriptionRef, event);
    return event.eventId;
  }
}
