# build stage
FROM golang:1.23-alpine AS build
WORKDIR /src
COPY . .
RUN go build -trimpath -ldflags "-s -w" -o /out/telemetry-ingest ./main.go

# runtime stage
FROM alpine:3.23
RUN adduser -D -H -s /sbin/nologin app
USER app
WORKDIR /app
COPY --from=build /out/telemetry-ingest /app/telemetry-ingest
EXPOSE 8080
ENV LISTEN_ADDR=":8080" \
    MAX_BODY_BYTES="1024" \
    RATE_LIMIT_RPM="60" \
    RATE_BURST="20" \
    RATE_KEY_MODE="ip" \
    ENABLE_REQUEST_LOGGING="false" \
    UPSTREAM_TIMEOUT_MS="4000"
CMD ["/app/telemetry-ingest"]
