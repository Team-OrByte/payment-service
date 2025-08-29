import ballerina/http;
import ballerinax/stripe;
import ballerinax/mongodb;
import ballerina/io;
import ballerinax/kafka;
import ballerina/log;
// import payment_service.event_handler;
import ballerina/websocket;

// Global map to store WebSocket connections by user ID
map<websocket:Caller> wsConnections = {};

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

// Kafka Producer for outbox events
kafka:ProducerConfiguration producerConfiguration = {
    clientId: "payment-service-producer",
    acks: "all",
    retryCount: 3
};

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

        string paymentUrl = checkoutSession?.url is string ? <string>checkoutSession?.url : "";

        // Send payment URL to connected WebSocket client
        websocket:Caller? wsClient = wsConnections[paymentEvent.userId];
        if wsClient is websocket:Caller {
            json paymentMessage = {
                "type": "payment_url",
                "rideId": paymentEvent.rideId,
                "paymentUrl": paymentUrl,
                "status": "pending"
            };
            websocket:Error? sendResult = wsClient->writeMessage(paymentMessage);
            if sendResult is websocket:Error {
                io:println("Failed to send payment URL to WebSocket client: ", sendResult.message());
            }
        } else {
            io:println("No WebSocket connection found for user: ", paymentEvent.userId);
        }

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
        
        // Get the payment record to find the rideId for event emission
        map<json>|mongodb:Error? paymentRecord = self.paymentCollection->findOne({ [idField]: objectId });
        if paymentRecord is map<json> {
            json? rideIdJson = paymentRecord["rideId"];
            json? userIdJson = paymentRecord["userId"];
            json? amountJson = paymentRecord["amount"];
            
            if rideIdJson is json && userIdJson is json && amountJson is json {
                string rideId = rideIdJson.toString();
                string userId = userIdJson.toString();

                // Send payment status update to connected WebSocket client
                websocket:Caller? wsClient = wsConnections[userId];
                if wsClient is websocket:Caller {
                    json statusMessage = {
                        "type": "payment_status_update",
                        "rideId": rideId,
                        "status": status,
                        "stripeSessionId": objectId
                    };
                    websocket:Error? sendResult = wsClient->writeMessage(statusMessage);
                    if sendResult is websocket:Error {
                        io:println("Failed to send payment status update to WebSocket client: ", sendResult.message());
                    }
                } else {
                    io:println("No WebSocket connection found for user: ", userId);
                }
            }
        }
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

kafka:ConsumerConfiguration consumerConfiguration = {
    groupId: "payments",
    topics: ["payment-events"],
    pollingInterval: 1,
    autoCommit: false
};

listener kafka:Listener kafkaListener = new (kafka:DEFAULT_URL,consumerConfiguration);
service on kafkaListener {
    private final mongodb:Database paymentsDb;
    private final mongodb:Collection paymentCollection;

    function init() returns error? {
        self.paymentsDb = check mongoClient->getDatabase(database);
        self.paymentCollection = check self.paymentsDb->getCollection(collection);
    }

    private function create\-payment(PaymentEvent paymentEvent) returns Response|error {
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

        stripe:Checkout\.session checkoutSession = check stripeClient->/checkout/sessions.post(sessionParams);

        // Save initial payment record (status = pending)
        check self.paymentCollection->insertOne({
            "userId": paymentEvent.userId,
            "rideId": paymentEvent.rideId,
            "amount": amount,
            "stripeSessionId": checkoutSession?.id,
            "status": PENDING
        });

        // Emit payment outbox event
        // string sessionId = checkoutSession?.id is string ? <string>checkoutSession?.id : "";
        string paymentUrl = checkoutSession?.url is string ? <string>checkoutSession?.url : "";

        // Send payment URL to connected WebSocket client
        websocket:Caller? wsClient = wsConnections[paymentEvent.userId];
        if wsClient is websocket:Caller {
            json paymentMessage = {
                "type": "payment_url",
                "rideId": paymentEvent.rideId,
                "paymentUrl": paymentUrl,
                "status": "pending"
            };
            websocket:Error? sendResult = wsClient->writeMessage(paymentMessage);
            if sendResult is websocket:Error {
                io:println("Failed to send payment URL to WebSocket client: ", sendResult.message());
            }
        } else {
            io:println("No WebSocket connection found for user: ", paymentEvent.userId);
        }

        Response response = { statusCode: 200, data: checkoutSession?.url };
        return response;
    }

	remote function onConsumerRecord(kafka:Caller caller, kafka:BytesConsumerRecord[] records) returns kafka:Error? {
        
        //process the event here
        io:println("Received payment event: ", records[0].value);
        PaymentEvent|error paymentEvent = records[0].value.toJsonString().fromJsonWithType(PaymentEvent);
        if paymentEvent is error {
            io:println("Failed to parse payment event: ", paymentEvent.message());
            return;
        }
        Response|error result = self.create\-payment(<PaymentEvent>paymentEvent);
        if result is error {
            io:println("Failed to create payment: ", result.message());
            return;
        }
        io:println("Payment created successfully");

        kafka:Error? commitResult = caller->commit();

        if commitResult is kafka:Error {
            log:printError("Error occurred while committing the offsets for the consumer ", 'error = commitResult);
        }
	}
}

service /basic/ws on new websocket:Listener(9091) {
   resource function get .() returns websocket:Service|websocket:Error {
       return new WsService();
   }
}

service class WsService {
    *websocket:Service;
    
    private string? userId = ();
    
    remote function onOpen(websocket:Caller caller) returns error? {
        io:println("Opened a WebSocket connection");
        check caller->writeMessage("Connected! Please send your user ID to register for payment notifications.");
    }
    
    remote function onMessage(websocket:Caller caller, json data) returns websocket:Error? {
        io:println("Received WebSocket message: ", data);
        
        // Check if this is a user ID registration message
        if data is map<json> {
            json? userIdJson = data["userId"];
            json? typeJson = data["type"];
            
            if typeJson is string && typeJson == "register" && userIdJson is string {
                string userId = userIdJson.toString();
                self.userId = userId;
                wsConnections[userId] = caller;
                io:println("Registered WebSocket connection for user: ", userId);
                
                json response = {
                    "type": "registration_success",
                    "message": "Successfully registered for payment notifications",
                    "userId": userId
                };
                check caller->writeMessage(response);
            } else {
                json response = {
                    "type": "error",
                    "message": "Invalid message format. Send {\"type\": \"register\", \"userId\": \"your_user_id\"}"
                };
                check caller->writeMessage(response);
            }
        }
    }
    
    remote function onPing(websocket:Caller caller, byte[] data) returns error? {
        io:println("Ping received");
        check caller->pong(data);
    }
 
    remote function onPong(websocket:Caller caller, byte[] data) {
        io:println("Pong received");
    }

    remote function onIdleTimeout(websocket:Caller caller) {
        io:println("WebSocket connection timed out");
        self.cleanupConnection();
    }

    remote function onClose(websocket:Caller caller, int statusCode, string reason) {
        io:println(string `Client closed connection with ${statusCode} because of ${reason}`);
        self.cleanupConnection();
    }

    remote function onError(websocket:Caller caller, error err) {
        io:println("WebSocket error: ", err.message());
        self.cleanupConnection();
    }
    
    private function cleanupConnection() {
        if self.userId is string {
            string userId = <string>self.userId;
            _ = wsConnections.remove(userId);
            io:println("Removed WebSocket connection for user: ", userId);
        }
    }
}