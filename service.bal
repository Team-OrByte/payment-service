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
            "amount": amount,
            "stripeSessionId": checkoutSession?.id,
            "status": PENDING
        });

        Response response = { statusCode: 200, data: checkoutSession?.url };
        return response;
    }

    // 2. Stripe Webhook (actual status comes here)
    resource function post webhook(http:Caller caller, http:Request req) returns error? {
        json|error payload = req.getJsonPayload();
        if payload is error {
            check caller->respond({ statusCode: 400, message: "Invalid payload" });
            return;
        }

        io:println("Webhook event received: ", payload.toJsonString());

        json eventTypeJson = check payload.'type;
        string eventType = eventTypeJson.toString();

        json dataJson = check payload.data;
        json dataObject = check dataJson.'object;

        if eventType == "checkout.session.completed" {
            json sessionIdJson = check dataObject.id;
            string sessionId = sessionIdJson.toString();
            io:println("Checkout session completed. Session ID: ", sessionId);

            mongodb:Update update = {
                set: { "status": SUCCEEDED }
            };
            _ = check self.paymentCollection->updateOne({ "stripeSessionId": sessionId }, update);

        } else if eventType == "checkout.session.expired" {
            json sessionIdJson = check dataObject.id;
            string sessionId = sessionIdJson.toString();
            io:println("Checkout session expired. Session ID: ", sessionId);

            mongodb:Update update = {
                set: { "status": EXPIRED }
            };
            _ = check self.paymentCollection->updateOne({ "stripeSessionId": sessionId }, update);

        } else if eventType == "payment_intent.succeeded" {
            json intentIdJson = check dataObject.id;
            string intentId = intentIdJson.toString();
            io:println("Payment intent succeeded. Intent ID: ", intentId);

            mongodb:Update update = {
                set: { "status": SUCCEEDED }
            };
            _ = check self.paymentCollection->updateOne({ "stripeIntentId": intentId }, update);

        } else if eventType == "payment_intent.payment_failed" {
            json intentIdJson = check dataObject.id;
            string intentId = intentIdJson.toString();
            io:println("Payment failed. Intent ID: ", intentId);

            mongodb:Update update = {
                set: { "status": FAILED }
            };
            _ = check self.paymentCollection->updateOne({ "stripeIntentId": intentId }, update);

        } else if eventType == "payment_intent.canceled" {
            json intentIdJson = check dataObject.id;
            string intentId = intentIdJson.toString();
            io:println("Payment intent canceled. Intent ID: ", intentId);

            mongodb:Update update = {
                set: { "status": CANCELED }
            };
            _ = check self.paymentCollection->updateOne({ "stripeIntentId": intentId }, update);

        } else {
            io:println("Unhandled event type: ", eventType);
        }

        check caller->respond({ statusCode: 200, message: "Webhook received" });
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
