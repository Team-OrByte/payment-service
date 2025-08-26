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

