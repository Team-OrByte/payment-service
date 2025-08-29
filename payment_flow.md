# Payment Flow Documentation (Ride → Stripe → WebSocket)

## 🔹 Sequence Diagram

```
 RideService      PaymentService        Stripe            Frontend
     |                  |                 |                  |
     |-- RIDE_ENDED --->|                 |                  |
     |                  |-- Create ------>|                  |
     |                  |   PaymentIntent |                  |
     |                  |<-- payment_url -|                  |
     |                  |-- WebSocket --->|                  |
     |                  |  (PAYMENT_CREATED)                 |
     |                  |                 |-- Redirect ----->|
     |                  |                 |   to Stripe      |
     |                  |                 |                  |
     |                  |                 |<-- Success/Fail -|
     |                  |<-- Webhook -----|                  |
     |                  |  (succeeded/failed)                |
     |                  |-- Update DB ----|                  |
     |                  |-- WebSocket --->|                  |
     |                  |  (PAYMENT_STATUS)                  |
     |                  |                 |-- Update UI ---->|
```

---

## 🔹 Success Path

- Ride ends → Payment created → User pays successfully → Stripe webhook → Payment DB updated → WebSocket `"succeeded"` → Frontend shows receipt.

---

## 🔹 Failure Path

- Ride ends → Payment created → User fails payment (cancel/decline/expire) → Stripe webhook → Payment DB updated → WebSocket `"failed"` → Frontend shows retry page with reason.

---
