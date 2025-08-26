# Stripe Webhook Setup

Create a Stripe account and get your Secret Key from the Stripe Dashboard.

The backend exposes a webhook endpoint:

```
/payment-service/webhook
```

Stripe will call this URL to update payment status.

## Local Development:

Use the Stripe CLI to forward events:

```bash
stripe listen --forward-to localhost:9090/payment-service/webhook
```

## Production:

1. Deploy your Ballerina service to a cloud server (AWS EC2, Render, Railway, etc.).

2. Make the service publicly accessible (e.g. `https://yourdomain.com/payment-service/webhook`).

3. In Stripe Dashboard → Developers → Webhooks → Add Endpoint, paste your webhook URL.

Stripe will then send events (e.g. `checkout.session.completed`, `payment_intent.payment_failed`) directly to your backend.
