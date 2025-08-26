type Response record {
    int statusCode;
    string message?;
    anydata data?;
};

public type PaymentEvent record {|
    string rideId;
    string userId;
    string fare;
|};

public type StripeWebhookPayload record {|
    string eventType;
    string objectId;
|};

public enum StripeEventType {
    CHECKOUT_SESSION_COMPLETED = "checkout.session.completed",
    CHECKOUT_SESSION_EXPIRED = "checkout.session.expired",
    PAYMENT_INTENT_SUCCEEDED = "payment_intent.succeeded",
    PAYMENT_INTENT_PAYMENT_FAILED = "payment_intent.payment_failed",
    PAYMENT_INTENT_CANCELED = "payment_intent.canceled"
}

public type WebhookEventHandler record {|
    PaymentStatus status;
    string idField;
    string logMessage;
|};

public enum PaymentStatus {
    PENDING = "pending",
    SUCCEEDED = "succeeded",
    FAILED = "failed",
    CANCELED = "canceled",
    EXPIRED = "expired"
};
