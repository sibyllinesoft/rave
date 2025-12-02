FROM golang:1.21-alpine AS builder

WORKDIR /app
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 go build -o auth-manager ./cmd/auth-manager

FROM alpine:3.19
RUN apk --no-cache add ca-certificates
COPY --from=builder /app/auth-manager /usr/local/bin/auth-manager
ENTRYPOINT ["/usr/local/bin/auth-manager"]
