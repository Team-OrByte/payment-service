# Payment Service

[![CI](https://github.com/Team-OrByte/payment-service/actions/workflows/automation.yaml/badge.svg)](https://github.com/Team-OrByte/payment-service/actions/workflows/automation.yaml)
[![Docker Image](https://img.shields.io/badge/docker-thetharz%2Forbyte__payment__service-blue)](https://hub.docker.com/r/thetharz/orbyte_payment_service)

A Ballerina-based payment processing microservice that integrates with Stripe for payment processing, Kafka for event streaming, MongoDB for data persistence, and WebSocket for real-time notifications. This service handles ride payment transactions within a ride-hailing application ecosystem.

## How Ballerina is Used

This project leverages Ballerina's cloud-native capabilities and built-in connectors for:

- **Service Orchestration**: Ballerina services handle payment workflows and event processing
- **Database Integration**: MongoDB connector for persistent payment record storage
- **Message Streaming**: Kafka consumer for processing payment events from ride service
- **API Integration**: Stripe connector for secure payment processing
- **WebSocket Communication**: Real-time payment status updates to frontend clients
- **Configuration Management**: External configuration support for environment-specific settings

### Key Ballerina Features Used

- Configurable variables for environment-specific settings
- Built-in connectors for MongoDB, Kafka, and Stripe
- WebSocket service for real-time communication
- JSON data binding and type safety
- Error handling and logging

## Configuration Example

Create a `Config.toml` file with the following structure:

```toml
# Stripe Configuration
stripeSecretKey = "sk_test_your_stripe_secret_key_here"
successRedirectUrl = "http://localhost:3000/success"
cancelRedirectUrl = "http://localhost:3000/cancel"

# MongoDB Configuration
host = "localhost"  # Use "payment_service_mongodb" for Docker
port = 27017
username = "your_mongodb_username"
password = "your_mongodb_password"
database = "payment-service-db"
collection = "payments"

# Kafka Configuration
kafkaBootstrapServers = "localhost:9092"  # Use "kafka:9092" for Docker
```

## API Endpoints

### WebSocket Endpoints

#### Payment WebSocket Connection

- **Path**: `/payment-ws`
- **Port**: `9091`
- **Method**: WebSocket upgrade
- **Query Parameters**:
  - `userId` (optional): User ID for automatic registration
- **Description**: Establishes WebSocket connection for real-time payment notifications

**Connection URL Format**:

```
ws://localhost:9091/payment-ws?userId=your_user_id
```

**Message Types**:

1. **Registration Message** (if userId not provided in URL):

```json
{
  "type": "register",
  "userId": "user123"
}
```

2. **Registration Success Response**:

```json
{
  "type": "registration_success",
  "message": "Successfully registered for payment notifications",
  "userId": "user123"
}
```

3. **Payment URL Notification**:

```json
{
  "type": "payment_url",
  "rideId": "ride123",
  "paymentUrl": "https://checkout.stripe.com/pay/...",
  "status": "pending"
}
```

### Kafka Consumer Endpoints

#### Payment Events Consumer

- **Topic**: `payment-events`
- **Group ID**: `payments`
- **Method**: Kafka consumer
- **Description**: Processes incoming payment events from ride service

**Expected Event Format**:

```json
{
  "rideId": "ride123",
  "userId": "user456",
  "fare": "25.50"
}
```

**Processing Flow**:

1. Receives payment event from Kafka
2. Creates Stripe checkout session
3. Stores payment record in MongoDB with `pending` status
4. Sends payment URL via WebSocket to registered user

### Stripe Webhook Endpoint

#### Payment Status Updates

- **Path**: `/payment-service/webhook`
- **Method**: `POST`
- **Description**: Receives payment status updates from Stripe

**Webhook Events Handled**:

- `checkout.session.completed`
- `checkout.session.expired`
- `payment_intent.succeeded`
- `payment_intent.payment_failed`
- `payment_intent.canceled`

## Payment Flow

1. **Ride Completion**: Ride service publishes payment event to Kafka
2. **Payment Creation**: Payment service creates Stripe checkout session
3. **WebSocket Notification**: Payment URL sent to user via WebSocket
4. **User Payment**: User redirected to Stripe for payment
5. **Webhook Processing**: Stripe sends status updates via webhook
6. **Status Update**: Payment status updated in MongoDB
7. **Real-time Notification**: Status update sent via WebSocket

## License

This project is part of the OrByte team's ride-hailing application ecosystem.
