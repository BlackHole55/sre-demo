FROM golang:1.26-alpine AS builder
WORKDIR /src
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux go build -o /authservice .

FROM alpine:3.19
RUN apk add --no-cache ca-certificates
COPY --from=builder /authservice /authservice
EXPOSE 9555
ENTRYPOINT ["/authservice"]