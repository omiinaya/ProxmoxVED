FROM golang:1.25-alpine AS build
WORKDIR /src
COPY . .
RUN go build -trimpath -ldflags "-s -w" -o /out/telemetry-ingest .

FROM alpine:3.23
WORKDIR /app
COPY --from=build /out/telemetry-ingest /app/telemetry-ingest
EXPOSE 8080
CMD ["/app/telemetry-ingest"]
