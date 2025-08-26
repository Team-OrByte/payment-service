# Payment Flow Documentation (Ride → Stripe → WebSocket)

This document describes how the payment lifecycle works in the bike rental system after a ride ends. It covers both **successful** and **failed** payments, and explains how the frontend, backend, and Stripe interact.

---

## 🔹 Actors

- **Ride Service** → Publishes events when rides end.
- **Payment Service** → Handles payment creation, Stripe interaction, webhook processing, and WebSocket notifications.
- **Frontend (Client)** → Displays pages and reacts to WebSocket messages.
- **Stripe** → Processes payments and sends webhooks.

---

## 🔹 Flow Overview

1. **Ride ends**

   - Ride Service publishes a `RIDE_ENDED` event with `rideId`, `userId`, and `amount`.

2. **Payment Service creates payment**

   - Listens for `RIDE_ENDED`.
   - Creates a Stripe Checkout Session or PaymentIntent with `metadata: { rideId, userId }`.
   - Stores payment in DB with status = `pending`.
   - Sends WebSocket message to frontend:

     ```json
     {
       "type": "PAYMENT_CREATED",
       "rideId": "ride_123",
       "paymentUrl": "https://checkout.stripe.com/session/xyz"
     }
     ```

3. **Frontend redirects user to Stripe Checkout**

   - User enters card details.
   - Payment either **succeeds** or **fails**.

4. **Stripe sends webhook → Payment Service**

   - Stripe sends `checkout.session.completed` on success.
   - Stripe sends `payment_intent.payment_failed` or `checkout.session.expired` on failure.

5. **Payment Service updates DB**

   - On success → mark as `succeeded`.
   - On failure → mark as `failed`, store failure reason.

6. **Payment Service notifies frontend via WebSocket**

   - Success message:

     ```json
     {
       "type": "PAYMENT_STATUS",
       "rideId": "ride_123",
       "status": "succeeded"
     }
     ```

   - Failure message:

     ```json
     {
       "type": "PAYMENT_STATUS",
       "rideId": "ride_123",
       "status": "failed",
       "reason": "Card declined"
     }
     ```

7. **Frontend updates UI accordingly**

   - On success → redirect to `/receipt/:rideId`.
   - On failure → redirect to `/payment-retry/:rideId` and display error.

---

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
