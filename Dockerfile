FROM ballerina/ballerina:2201.12.7 AS builder

WORKDIR /app

COPY Ballerina.toml .
COPY Dependencies.toml .
COPY *.bal .
COPY modules/ modules/

RUN bal build

# Use Ballerina runtime image which includes all necessary native libraries
FROM ballerina/ballerina:2201.12.7-runtime

WORKDIR /app

COPY --from=builder /app/target/bin/payment_service.jar .

RUN mkdir -p logs

EXPOSE 9091

CMD ["java", "-jar", "payment_service.jar"]
