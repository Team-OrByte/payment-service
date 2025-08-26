import ballerina/http;
import ballerinax/stripe;
import ballerinax/mongodb;
import ballerina/io;

configurable string stripeSecretKey = ?;
configurable string successRedirectUrl = ?;
configurable string cancelRedirectUrl = ?;

configurable string host = ?;
configurable int port = ?;
configurable string username = ?;
configurable string password = ?;
configurable string database = ?;
configurable string collection = ?;

final mongodb:Client mongoClient = check new ({
    connection: {
        serverAddress: { host, port },
        auth: <mongodb:ScramSha256AuthCredential>{
            username,
            password,
            database
        }
    }
});

stripe:ConnectionConfig configuration = {
    auth: { token: stripeSecretKey }
};

stripe:Client stripeClient = check new (configuration);

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["POST", "PUT", "GET", "OPTIONS"],
        allowHeaders: ["Content-Type", "Access-Control-Allow-Origin", "X-Service-Name"]
    }
}
service /payment\-service on new http:Listener(9090) {

    private final mongodb:Database paymentsDb;
    private final mongodb:Collection paymentCollection;

    function init() returns error? {
        self.paymentsDb = check mongoClient->getDatabase(database);
        self.paymentCollection = check self.paymentsDb->getCollection(collection);
    }

    // 1. Create Checkout Session
    resource function post create\-payment(PaymentEvent paymentEvent) returns Response|error {
        decimal fareDecimal = check decimal:fromString(paymentEvent.fare);
        int amount = <int>(fareDecimal * 100);

        stripe:checkout_sessions_body sessionParams = {
            payment_method_types: ["card"],
            line_items: [
                {
                    price_data: {
                        currency: "usd",
                        product_data: { name: "Ride Payment" },
                        unit_amount: amount
                    },
                    quantity: 1
                }
            ],
            mode: "payment",
            success_url: successRedirectUrl,
            cancel_url: cancelRedirectUrl
        };

        stripe:Checkout\.session|error checkoutSession =
            stripeClient->/checkout/sessions.post(sessionParams);

        if checkoutSession is error {
            return error("Failed to create checkout session: " + checkoutSession.message());
        }

        // Save initial payment record (status = pending)
        check self.paymentCollection->insertOne({
            "userId": paymentEvent.userId,
            "rideId": paymentEvent.rideId,
            "amount": amount,
            "stripeSessionId": checkoutSession?.id,
            "status": PENDING
        });

        Response response = { statusCode: 200, data: checkoutSession?.url };
        return response;
    }

    // 2. Stripe Webhook (actual status comes here)
    resource function post webhook(http:Caller caller, http:Request req) returns error? {
        StripeWebhookPayload|error webhookPayload = self.parseWebhookPayload(req);
        if webhookPayload is error {
            check caller->respond({ statusCode: 400, message: "Invalid webhook payload" });
            return;
        }

        io:println("Webhook event received: ", webhookPayload.eventType);

        error? result = self.processWebhookEvent(webhookPayload);
        if result is error {
            io:println("Failed to process webhook event: ", result.message());
            check caller->respond({ statusCode: 500, message: "Internal server error" });
            return;
        }

        check caller->respond({ statusCode: 200, message: "Webhook processed successfully" });
    }

    private function parseWebhookPayload(http:Request req) returns StripeWebhookPayload|error {
        json payload = check req.getJsonPayload();
        
        string eventType = check payload.'type;
        json dataObject = check payload.data.'object;
        string objectId = check dataObject.id;

        // Validate that we have the required fields
        if eventType.trim().length() == 0 || objectId.trim().length() == 0 {
            return error("Missing required fields in webhook payload");
        }

        return {
            eventType,
            objectId
        };
    }

    private final map<WebhookEventHandler> eventHandlers = {
        [CHECKOUT_SESSION_COMPLETED]: {
            status: SUCCEEDED,
            idField: "stripeSessionId",
            logMessage: "Checkout session completed"
        },
        [CHECKOUT_SESSION_EXPIRED]: {
            status: EXPIRED,
            idField: "stripeSessionId",
            logMessage: "Checkout session expired"
        },
        [PAYMENT_INTENT_SUCCEEDED]: {
            status: SUCCEEDED,
            idField: "stripeIntentId",
            logMessage: "Payment intent succeeded"
        },
        [PAYMENT_INTENT_PAYMENT_FAILED]: {
            status: FAILED,
            idField: "stripeIntentId",
            logMessage: "Payment failed"
        },
        [PAYMENT_INTENT_CANCELED]: {
            status: CANCELED,
            idField: "stripeIntentId",
            logMessage: "Payment intent canceled"
        }
    };

    private function processWebhookEvent(StripeWebhookPayload payload) returns error? {
        WebhookEventHandler? handler = self.eventHandlers[payload.eventType];
        
        if handler is WebhookEventHandler {
            io:println(handler.logMessage, ". Object ID: ", payload.objectId);
            return self.updatePaymentStatus(payload.objectId, handler.status, handler.idField);
        } else {
            io:println("Unhandled event type: ", payload.eventType);
            return (); // No error for unhandled events
        }
    }

    private function updatePaymentStatus(string objectId, PaymentStatus status, string idField) returns error? {
        mongodb:Update update = {
            set: { "status": status }
        };
        _ = check self.paymentCollection->updateOne({ [idField]: objectId }, update);
    }


    // 3. Poll endpoint: frontend can check payment status
    resource function get status(string sessionId) returns Response|error {
        map<json>|mongodb:Error? result = self.paymentCollection->findOne({ "stripeSessionId": sessionId });
        if result is error || result is () {
            return { statusCode: 404, data: "Payment not found" };
        }
        
        json statusJson = result["status"];
        string status = statusJson.toString();
        return { statusCode: 200, data: status };
    }

    // 4. Health Check
    resource function get health(http:Request request) returns Response {
        return { statusCode: 200, data: "OK" };
    }
}
