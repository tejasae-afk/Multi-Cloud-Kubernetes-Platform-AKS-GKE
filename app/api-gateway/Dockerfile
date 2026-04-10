FROM golang:1.22.12-alpine3.21 AS build
WORKDIR /src

COPY go.mod ./
RUN go mod download

COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -trimpath -ldflags="-s -w" -o /out/api-gateway ./main.go

FROM gcr.io/distroless/static-debian12:nonroot
WORKDIR /app
COPY --from=build /out/api-gateway /app/api-gateway

USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/app/api-gateway"]
