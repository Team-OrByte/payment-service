import ballerina/log;
import ballerinax/kafka;

// Kafka Producer for outbox events
kafka:ProducerConfiguration producerConfiguration = {
    clientId: "payment-service-producer",
    acks: "all",
    retryCount: 3
};

final kafka:Producer paymentOutboxProducer;

function init() returns error? {
    paymentOutboxProducer = check new (kafka:DEFAULT_URL, producerConfiguration);
    log:printInfo("Payment outbox producer initialized");
}

public enum PaymentStatus {
    PENDING = "pending",
    SUCCEEDED = "succeeded",
    FAILED = "failed",
    CANCELED = "canceled",
    EXPIRED = "expired"
};

public type PaymentOutboxEvent record {|
    string eventType;
    string rideId;
    string userId;
    string paymentUrl;
    string amount;
    string stripeSessionId;
    PaymentStatus status;
|};

public isolated function producePaymentOutboxEvent(PaymentOutboxEvent outboxEvent) returns error? {
    kafka:Error? result = paymentOutboxProducer->send({
        topic: "payment-outbox-events",
        key: outboxEvent.rideId.toBytes(),
        value: outboxEvent.toJson().toString().toBytes()
    });
    
    if result is kafka:Error {
        return error("Failed to emit payment outbox event: " + result.message());
    }
    log:printInfo("Payment outbox event emitted successfully");
}
