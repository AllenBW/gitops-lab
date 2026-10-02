# Multi-stage: build in the full Go image, ship a tiny distroless one.
# The build stage runs on the builder's own platform and cross-compiles for the target,
# so CI can produce amd64 and arm64 images without slow emulation.
FROM --platform=$BUILDPLATFORM golang:1.22 AS build
WORKDIR /src
COPY go.mod ./
COPY *.go ./
ARG VERSION=dev
ARG TARGETOS TARGETARCH
RUN CGO_ENABLED=0 GOOS=$TARGETOS GOARCH=$TARGETARCH \
    go build -ldflags "-X main.version=${VERSION}" -o /hello .

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /hello /hello
# Numeric UID (distroless "nonroot" is 65532). Kubernetes can only enforce
# runAsNonRoot against a number; USER nonroot:nonroot fails with
# "image has non-numeric user (nonroot), cannot verify user is non-root".
USER 65532:65532
EXPOSE 8080
ENTRYPOINT ["/hello"]
