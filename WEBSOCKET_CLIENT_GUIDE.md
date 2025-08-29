# WebSocket Client Integration Guide

This guide explains how to connect to the payment service WebSocket to receive real-time payment notifications.

## Connection

Connect to the WebSocket endpoint:

```
ws://localhost:9090/basic/ws
```

## Client Registration

After connecting, you must register your user ID to receive payment notifications:

```json
{
  "type": "register",
  "userId": "your_user_id_here"
}
```

### Success Response

```json
{
  "type": "registration_success",
  "message": "Successfully registered for payment notifications",
  "userId": "your_user_id_here"
}
```

### Error Response

```json
{
  "type": "error",
  "message": "Invalid message format. Send {\"type\": \"register\", \"userId\": \"your_user_id\"}"
}
```

## Payment Notifications

Once registered, you'll receive the following types of notifications:

### Payment URL Notification

When a payment is created for your user ID:

```json
{
  "type": "payment_url",
  "rideId": "ride_123",
  "paymentUrl": "https://checkout.stripe.com/pay/cs_...",
  "status": "pending"
}
```

### Payment Status Update

When payment status changes (completed, failed, etc.):

```json
{
  "type": "payment_status_update",
  "rideId": "ride_123",
  "status": "succeeded",
  "stripeSessionId": "cs_..."
}
```

## Example JavaScript Client

```javascript
const ws = new WebSocket('ws://localhost:9090/basic/ws');

ws.onopen = function () {
  console.log('Connected to payment service');

  // Register with your user ID
  ws.send(
    JSON.stringify({
      type: 'register',
      userId: 'user_123',
    })
  );
};

ws.onmessage = function (event) {
  const data = JSON.parse(event.data);
  console.log('Received:', data);

  switch (data.type) {
    case 'registration_success':
      console.log('Successfully registered for payment notifications');
      break;

    case 'payment_url':
      console.log('Payment URL received:', data.paymentUrl);
      // Redirect user to payment URL or show in modal
      window.open(data.paymentUrl, '_blank');
      break;

    case 'payment_status_update':
      console.log('Payment status updated:', data.status);
      // Update UI based on payment status
      break;

    case 'error':
      console.error('Error:', data.message);
      break;
  }
};

ws.onerror = function (error) {
  console.error('WebSocket error:', error);
};

ws.onclose = function () {
  console.log('Disconnected from payment service');
};
```

## Connection Management

- The service automatically removes client mappings when connections are closed or time out
- Clients should handle reconnection logic and re-register their user ID
- Multiple connections for the same user ID will overwrite the previous connection
