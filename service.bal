import ballerinax/stripe;
import ballerinax/mongodb;
import ballerina/io;
import ballerinax/kafka;
import ballerina/log;
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

kafka:ConsumerConfiguration consumerConfiguration = {
    groupId: "payments",
    topics: ["payment-events"],
    pollingInterval: 1,
    autoCommit: false
};

configurable string kafkaBootstrapServers = ?;

listener kafka:Listener kafkaListener = new (kafkaBootstrapServers,consumerConfiguration);
service on kafkaListener {
    private final mongodb:Database paymentsDb;
    private final mongodb:Collection paymentCollection;

    function init() returns error? {
        self.paymentsDb = check mongoClient->getDatabase(database);
        self.paymentCollection = check self.paymentsDb->getCollection(collection);
    }

    private function create\-payment(PaymentEvent paymentEvent) returns Response|error {
        decimal fareDecimal = check decimal:fromString(paymentEvent.fare);
        int amount = <int>(fareDecimal * 100)/300;

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
        
        // Convert byte array to string first, then parse as JSON
        string|error jsonString = string:fromBytes(records[0].value);
        if jsonString is error {
            io:println("Failed to convert bytes to string: ", jsonString.message());
            return;
        }
        
        io:println("Parsed JSON string: ", jsonString);
        
        // Parse to JSON first, then convert to PaymentEvent
        json|error jsonData = jsonString.fromJsonString();
        if jsonData is error {
            io:println("Failed to parse JSON: ", jsonData.message());
            return;
        }
        
        PaymentEvent|error paymentEvent = jsonData.fromJsonWithType(PaymentEvent);
        if paymentEvent is error {
            io:println("Failed to parse payment event: ", paymentEvent.message());
            io:println("JSON data: ", jsonData);
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

service /payment\-ws on new websocket:Listener(9091) {
   resource function get .(string? userId) returns websocket:Service|websocket:Error {
       return new WsService(userId);
   }
}

service class WsService {
    *websocket:Service;
    
    private string? userId = ();
    
    function init(string? userId = ()) {
        self.userId = userId;
    }
    
    remote function onOpen(websocket:Caller caller) returns error? {
        io:println("Opened a WebSocket connection");
        
        if self.userId is string {
            string userId = <string>self.userId;
            wsConnections[userId] = caller;
            io:println("Registered WebSocket connection for user: ", userId);
            
            json response = {
                "type": "registration_success",
                "message": "Successfully registered for payment notifications",
                "userId": userId
            };
            check caller->writeMessage(response);
        } else {
            check caller->writeMessage("Connected! Please send your user ID to register for payment notifications.");
        }
    }
    
    remote function onMessage(websocket:Caller caller, json data) returns websocket:Error? {
        io:println("Received WebSocket message: ", data);
        
        // If user is already registered via URL, handle other message types
        if self.userId is string {
            json response = {
                "type": "info",
                "message": "User already registered via URL parameter"
            };
            check caller->writeMessage(response);
            return;
        }
        
        // Check if this is a user ID registration message (fallback for clients not using URL parameter)
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