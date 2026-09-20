FROM golang:1.24.8-bookworm AS build
ARG MINIO_VERSION=RELEASE.2025-10-15T17-29-55Z
ENV CGO_ENABLED=0 GOBIN=/out
RUN go install -trimpath -ldflags="-s -w" "github.com/minio/minio@${MINIO_VERSION}"

FROM debian:13.1-slim
RUN apt-get update && apt-get install -y --no-install-recommends ca-certificates \
    && groupadd --gid 1000 minio \
    && useradd --uid 1000 --gid minio --no-create-home --shell /usr/sbin/nologin minio \
    && rm -rf /var/lib/apt/lists/*
COPY --from=build /out/minio /usr/local/bin/minio
USER 1000:1000
EXPOSE 9000 9001
ENTRYPOINT ["/usr/local/bin/minio"]
