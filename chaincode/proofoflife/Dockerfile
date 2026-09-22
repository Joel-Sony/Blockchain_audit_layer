# Builds proofoflife as a standalone chaincode-as-a-service container.
# We build and run this ourselves (docker build / docker run), rather than
# letting the peer build it — see docs/decisions.md ADR-004 for why.
FROM golang:1.25-alpine AS build
WORKDIR /src
COPY . .
RUN go build -o /proofoflife .

FROM alpine:latest
COPY --from=build /proofoflife /proofoflife
EXPOSE 9999
CMD ["/proofoflife"]
