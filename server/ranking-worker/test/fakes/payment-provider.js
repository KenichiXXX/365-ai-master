export class FakePaymentProvider {
  constructor() { this.events = new Map(); this.subscriptions = new Map(); this.available = true; }
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
  add(event) {
    this.events.set(event.eventId, event);
    this.subscriptions.set(event.subscriptionRef, event);
    return event.eventId;
  }
}
