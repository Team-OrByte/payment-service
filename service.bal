import ballerina/http;
import ballerinax/stripe;

configurable string stripeSecretKey = ?;

stripe:ConnectionConfig configuration = {
    auth: {
        token: stripeSecretKey
    }
};

stripe:Client stripeClient = check new (configuration);

@http:ServiceConfig {
    cors: {
        allowOrigins: ["*"],
        allowMethods: ["POST", "PUT", "GET", "POST", "OPTIONS"],
        allowHeaders: ["Content-Type", "Access-Control-Allow-Origin", "X-Service-Name"]
    }
}
service /payment\-service on new http:Listener(9090) {

    resource function get create\-payment(http:Request request) returns Response|error {
        // Create a checkout session for frontend integration
        stripe:checkout_sessions_body sessionParams = {
            payment_method_types: ["card"],
            line_items: [
                {
                    price_data: {
                        currency: "usd",
                        product_data: {
                            name: "Sample Product"
                        },
                        unit_amount: 500 // $5.00 in cents
                    },
                    quantity: 1
                }
            ],
            mode: "payment",
            success_url: "http://localhost:3000/success",
            cancel_url: "http://localhost:3000/cancel"
        };

        stripe:Checkout\.session|error checkoutSession = stripeClient->/checkout/sessions.post(sessionParams);
        
        if checkoutSession is error {
            return error("Failed to create checkout session: " + checkoutSession.message());
        }
        
        // Return the checkout URL for frontend

        Response response = {
            statusCode: 200,
            data: checkoutSession?.url
        };
        
        return response;
    }

    resource function get create\-payment\-intent(http:Request request) returns Response|error {
        stripe:payment_intents_body params = {
            amount: 500, // $5.00 in cents
            currency: "usd",
            capture_method: "automatic",
            confirmation_method: "automatic"
        };

        stripe:Payment_intent|error paymentIntent = stripeClient->/payment_intents.post(params);
        
        if paymentIntent is error {
            return error("Failed to create payment intent: " + paymentIntent.message());
        }
        
        // Return client secret for frontend Elements integration

        Response response = {
            statusCode: 200,
            data: paymentIntent?.client_secret
        };
        
        return response;
    }

    resource function get health(http:Request request) returns Response {
        Response response = {
            statusCode: 200
        };
        
        return response;
    }
}
