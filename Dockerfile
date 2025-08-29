FROM ballerina/ballerina:2201.12.7 AS builder

WORKDIR /app

COPY Ballerina.toml .
COPY Dependencies.toml .
COPY *.bal .
COPY modules/ modules/

RUN bal build

# Use Eclipse Temurin Java runtime image for running the compiled JAR
FROM eclipse-temurin:17-jre

WORKDIR /app

COPY --from=builder /app/target/bin/payment_service.jar .

RUN mkdir -p logs

EXPOSE 9091

CMD ["java", "-jar", "payment_service.jar"]
