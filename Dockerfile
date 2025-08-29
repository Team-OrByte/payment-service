FROM ballerina/ballerina:2201.12.7 AS builder

WORKDIR /app

# Copy only Ballerina.toml first to cache dependencies
COPY Ballerina.toml .

# Run dependency resolution before copying source code
RUN bal pull

# Copy source code (all files except Dependencies.toml)
COPY . .

# Run build (Ballerina will recreate Dependencies.toml)
RUN bal build

# Use Eclipse Temurin Java runtime image for running the compiled JAR
FROM eclipse-temurin:17-jre

WORKDIR /app

# Copy JAR from builder stage
COPY --from=builder /app/target/bin/payment_service.jar .

RUN mkdir -p logs

EXPOSE 9091

CMD ["java", "-jar", "payment_service.jar"]
