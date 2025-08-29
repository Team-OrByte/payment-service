FROM ballerina/ballerina:2201.12.7 AS builder

WORKDIR /app

# Copy only the dependency files first to leverage Docker cache
COPY Ballerina.toml .
COPY Dependencies.toml .

# Make Dependencies.toml writable
RUN chmod 666 Dependencies.toml
# Copy the rest of the source code
COPY . .

# Build (this will auto-pull dependencies)
RUN bal build

# Use Eclipse Temurin Java runtime image for running the compiled JAR
FROM eclipse-temurin:17-jre

WORKDIR /app

# Copy JAR from builder stage
COPY --from=builder /app/target/bin/payment_service.jar .

RUN mkdir -p logs

EXPOSE 9091

CMD ["java", "-jar", "payment_service.jar"]
