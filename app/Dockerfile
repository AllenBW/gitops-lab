# Multi-stage: build in the full Go image, ship a tiny distroless one.
FROM golang:1.22 AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -ldflags "-X main.version=${VERSION}" -o /hello .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /hello /hello
USER nonroot:nonroot
EXPOSE 8080
ENTRYPOINT ["/hello"]
