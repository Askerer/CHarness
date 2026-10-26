# syntax=docker/dockerfile:1

# ==============================================================================
# Stage 1: Build the Headless Codex Agent Harness Binaries
# ==============================================================================
FROM rust:bookworm AS builder

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    build-essential \
    clang \
    cmake \
    curl \
    pkg-config \
    libcap-dev \
    libssl-dev \
    ca-certificates \
    git \
    python3 \
    && rm -rf /var/lib/apt/lists/*

# Pre-fetch Codex's prebuilt sandbox-enabled rusty_v8 archive & binding in a cached layer
# (upstream denoland/rusty_v8 does not host the `ptrcomp_sandbox_release` build variant).
ENV RUSTY_V8_VERSION=152.2.0 \
    RUSTY_V8_MIRROR=https://github.com/openai/codex/releases/download \
    RUSTY_V8_MIRROR_TAG=rusty-v8-v152.2.0 \
    RUSTY_V8_ARCHIVE=/opt/rusty_v8/librusty_v8.a.gz \
    RUSTY_V8_SRC_BINDING_PATH=/opt/rusty_v8/src_binding.rs

RUN set -eux; \
    arch="$(uname -m)"; \
    case "$arch" in \
        x86_64) target="x86_64-unknown-linux-gnu" ;; \
        aarch64|arm64) target="aarch64-unknown-linux-gnu" ;; \
        *) echo "Unsupported architecture: $arch" >&2; exit 1 ;; \
    esac; \
    mkdir -p /opt/rusty_v8; \
    curl -fsSL "${RUSTY_V8_MIRROR}/${RUSTY_V8_MIRROR_TAG}/librusty_v8_ptrcomp_sandbox_release_${target}.a.gz" -o "${RUSTY_V8_ARCHIVE}"; \
    curl -fsSL "${RUSTY_V8_MIRROR}/${RUSTY_V8_MIRROR_TAG}/src_binding_ptrcomp_sandbox_release_${target}.rs" -o "${RUSTY_V8_SRC_BINDING_PATH}"

WORKDIR /src/codex
COPY .cargo ./.cargo
COPY codex-rs ./codex-rs

WORKDIR /src/codex/codex-rs

# Compile only the headless Agent Harness and Sandbox binaries:
# - codex-exec: Non-interactive / JSONL streaming Agent Harness CLI
# - codex-app-server: Bidirectional JSON-RPC 2.0 Agent Harness Server (stdio / ws / unix)
# - exec-server: Remote/Sandbox Process & Filesystem JSON-RPC Executor
# - codex-linux-sandbox: Landlock + seccomp + bubblewrap Linux sandbox helper
# - bwrap: Vendored Bubblewrap sandbox binary
# - apply_patch: Patch applicator tool helper
# - codex-execpolicy: Starlark execution policy verifier
# - codex-code-mode-host: Isolated V8 code-mode runtime host
# - codex-responses-api-proxy: Credential-isolating Responses API proxy
RUN --mount=type=cache,target=/usr/local/cargo/registry \
    --mount=type=cache,target=/usr/local/cargo/git \
    --mount=type=cache,target=/src/codex/codex-rs/target \
    cargo build --release \
    -p codex-exec --bin codex-exec \
    -p codex-app-server --bin codex-app-server --bin exec-server \
    -p codex-linux-sandbox --bin codex-linux-sandbox \
    -p codex-bwrap --bin bwrap \
    -p codex-apply-patch --bin apply_patch \
    -p codex-execpolicy --bin codex-execpolicy \
    -p codex-code-mode-host --bin codex-code-mode-host \
    -p codex-responses-api-proxy --bin codex-responses-api-proxy \
    && mkdir -p /out \
    && cp \
        target/release/codex-exec \
        target/release/codex-app-server \
        target/release/exec-server \
        target/release/codex-linux-sandbox \
        target/release/bwrap \
        target/release/apply_patch \
        target/release/codex-execpolicy \
        target/release/codex-code-mode-host \
        target/release/codex-responses-api-proxy \
        /out/

# ==============================================================================
# Stage 2: Minimal Docker Sandbox Runtime for Codex Agent Harness
# ==============================================================================
FROM ubuntu:24.04 AS runtime

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends \
    bash \
    bubblewrap \
    ca-certificates \
    curl \
    dnsutils \
    fd-find \
    git \
    iproute2 \
    ipset \
    iptables \
    jq \
    libcap2 \
    libssl3t64 \
    python3 \
    ripgrep \
    tini \
    && rm -rf /var/lib/apt/lists/*

# Create non-root sandbox user (`ubuntu:24.04` has `ubuntu:ubuntu` at UID/GID 1000; rename both user and group to `codex`)
RUN (id -u ubuntu >/dev/null 2>&1 && usermod -l codex -d /home/codex -m ubuntu && groupmod -n codex ubuntu) \
    || useradd -m -u 1000 -s /bin/bash codex \
    && mkdir -p /workspace /home/codex/.codex /etc/codex \
    && chown -R codex:codex /workspace /home/codex

# Copy Harness binaries from builder
COPY --from=builder /out/codex-exec /usr/local/bin/codex-exec
COPY --from=builder /out/codex-app-server /usr/local/bin/codex-app-server
COPY --from=builder /out/exec-server /usr/local/bin/exec-server
COPY --from=builder /out/codex-linux-sandbox /usr/local/bin/codex-linux-sandbox
COPY --from=builder /out/bwrap /usr/local/bin/bwrap
COPY --from=builder /out/apply_patch /usr/local/bin/apply_patch
COPY --from=builder /out/codex-execpolicy /usr/local/bin/codex-execpolicy
COPY --from=builder /out/codex-code-mode-host /usr/local/bin/codex-code-mode-host
COPY --from=builder /out/codex-responses-api-proxy /usr/local/bin/codex-responses-api-proxy

# Copy Docker Sandbox entrypoint, unified CLI shim, and egress firewall script
COPY docker/codex /usr/local/bin/codex
COPY docker/entrypoint.sh /usr/local/bin/docker-entrypoint.sh
COPY docker/init_firewall.sh /usr/local/bin/init_firewall.sh

RUN sed -i 's/\r$//' \
    /usr/local/bin/codex \
    /usr/local/bin/docker-entrypoint.sh \
    /usr/local/bin/init_firewall.sh \
    && chmod +x \
    /usr/local/bin/codex \
    /usr/local/bin/codex-exec \
    /usr/local/bin/codex-app-server \
    /usr/local/bin/exec-server \
    /usr/local/bin/codex-linux-sandbox \
    /usr/local/bin/bwrap \
    /usr/local/bin/apply_patch \
    /usr/local/bin/codex-execpolicy \
    /usr/local/bin/codex-code-mode-host \
    /usr/local/bin/codex-responses-api-proxy \
    /usr/local/bin/docker-entrypoint.sh \
    /usr/local/bin/init_firewall.sh \
    && ln -sf /usr/local/bin/apply_patch /usr/local/bin/applypatch

ENV CODEX_HOME=/home/codex/.codex \
    HARNESS_MODE=exec \
    HARNESS_LISTEN_URL=ws://0.0.0.0:8080 \
    EXEC_SERVER_LISTEN_URL=ws://0.0.0.0:31987

WORKDIR /workspace
USER codex

EXPOSE 8080 31987

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/docker-entrypoint.sh"]
CMD ["--help"]
