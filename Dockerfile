FROM ballerina/ballerina:2201.12.7 AS builder

WORKDIR /app

COPY Ballerina.toml Dependencies.toml Config.toml ./
COPY *.bal ./
COPY modules/ ./modules/

RUN bal build

FROM eclipse-temurin:21-jre-alpine

WORKDIR /app

# Install required native libraries for Netty TCNative
RUN apk add --no-cache \
    libc6-compat \
    openssl \
    openssl-dev \
    apr \
    apr-dev

COPY --from=builder /app/target/bin/payment_service.jar .

RUN mkdir -p logs

EXPOSE 8090

# Add JVM arguments to handle native library loading
CMD ["java", "-Djava.library.path=/usr/lib", "-Dio.netty.native.workdir=/tmp", "-jar", "payment_service.jar"]