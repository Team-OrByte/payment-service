FROM ballerina/ballerina:2201.12.7 AS builder

WORKDIR /app

# Copy the entire project, not just a few files
COPY . .

# Run the build
RUN bal build --offline || bal build

# Use Eclipse Temurin Java runtime image for running the compiled JAR
FROM eclipse-temurin:17-jre

WORKDIR /app

# Copy JAR from builder stage
COPY --from=builder /app/target/bin/payment_service.jar .

RUN mkdir -p logs

EXPOSE 9091

CMD ["java", "-jar", "payment_service.jar"]
