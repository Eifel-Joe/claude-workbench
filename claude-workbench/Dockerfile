# Home Assistant's multi-arch Alpine base (amd64 + arm64). Pinned here instead
# of build.yaml, which the Supervisor deprecated. Deliberately no ARG BUILD_FROM:
# older Supervisor versions pass their own default ({arch}-base:latest, the
# newest Alpine) and would silently replace this base through it.
FROM ghcr.io/home-assistant/base:3.24

LABEL \
    org.opencontainers.image.title="Home Assistant App: Claude Workbench" \
    org.opencontainers.image.description="Workbench for Anthropic's Claude Code CLI in Home Assistant" \
    org.opencontainers.image.source="https://github.com/Eifel-Joe/claude-workbench" \
    org.opencontainers.image.licenses="MIT"

# Install packages in a single layer to minimize image size.
# Node.js and npm are kept for the image-service dependency.
# ttyd and tmux are baked in on purpose: they used to be installed by run.sh on
# every container start, which made startup depend on the Alpine mirrors being
# reachable and aborted the add-on when they were not.
# coreutils for GNU timeout: run.sh puts startup downloads under a time limit,
# and BusyBox timeout signals only the process it started, so an `apk add` run
# by persist-install would outlive the cut-off and keep the apk database locked.
# apk upgrade first: the base image is only as fresh as its last publish, and
# Alpine ships security fixes as package revisions in between (heytcass
# 6641bfe0, from owine's fork; nsleigh, ESJavadex/claude-code-ha@a1f0f2da).
RUN apk upgrade --no-cache \
    && apk add --no-cache \
    coreutils \
    nodejs \
    npm \
    ttyd \
    tmux \
    bash \
    curl \
    nano \
    python3 \
    py3-pip \
    py3-requests \
    py3-aiohttp \
    py3-yaml \
    py3-beautifulsoup4 \
    jq \
    yq \
    git \
    vim \
    wget \
    tree

# Every RUN below pipes a download into another command. Without pipefail, a
# failed curl is invisible: the pipeline reports the exit status of the last
# command, so the build happily continues on an empty or error payload. bash is
# installed by the layer above, so it is available from here on.
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

# The Supervisor passes BUILD_ARCH (amd64|aarch64) as a --build-arg. A plain
# `docker build` falls back to BuildKit's TARGETARCH, then to the build host.
# Only 64-bit targets exist: Home Assistant ended 32-bit support with 2025.12,
# and the base image above covers amd64 and arm64 only.
ARG BUILD_ARCH
ARG TARGETARCH

RUN ADDON_ARCH="${BUILD_ARCH}"; \
    if [ -z "${ADDON_ARCH}" ]; then \
        case "${TARGETARCH}" in \
            amd64) ADDON_ARCH="amd64" ;; \
            arm64) ADDON_ARCH="aarch64" ;; \
        esac; \
    fi; \
    if [ -z "${ADDON_ARCH}" ]; then \
        case "$(uname -m)" in \
            x86_64)        ADDON_ARCH="amd64" ;; \
            aarch64|arm64) ADDON_ARCH="aarch64" ;; \
        esac; \
    fi; \
    case "${ADDON_ARCH}" in \
        amd64|aarch64) ;; \
        *) echo "Unsupported architecture (BUILD_ARCH='${BUILD_ARCH}' TARGETARCH='${TARGETARCH}' uname='$(uname -m)'); only amd64 and aarch64 are built" && exit 1 ;; \
    esac; \
    printf '%s\n' "${ADDON_ARCH}" > /etc/addon-arch && \
    echo "Resolved add-on architecture: ${ADDON_ARCH} (BUILD_ARCH='${BUILD_ARCH}' TARGETARCH='${TARGETARCH}' uname='$(uname -m)')"

# Install Claude Code CLI: native latest, npm as fallback.
# install.sh ends by running "claude install", an interactive TUI that never
# finishes without a TTY, so the build hung forever and the npm fallback never
# ran (upstream issue #44). The timeout turns that hang into a failure the ||
# catches; 300s leaves room for the binary download on slow hosts. A
# half-finished native install is removed before the fallback, because run.sh
# links /root/.local/bin/claude onto PATH ahead of the npm binary.
RUN (timeout 300 bash -c "curl -fsSL https://claude.ai/install.sh | bash" \
    && ln -sf /root/.local/bin/claude /usr/local/bin/claude) \
    || { rm -f /root/.local/bin/claude; npm install -g @anthropic-ai/claude-code; }

# Install Home Assistant CLI (ha command), latest release. Its asset names use
# the same arch names as the add-on (ha_amd64, ha_aarch64). The tag comes from
# where github.com redirects releases/latest (.../releases/tag/<tag>); GitHub's
# REST API allows 60 unauthenticated requests per hour per IP and failed CI
# builds with 403.
RUN HA_ARCH=$(cat /etc/addon-arch) && \
    echo "Fetching latest Home Assistant CLI version..." && \
    HA_URL=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/home-assistant/cli/releases/latest) && \
    HA_VERSION="${HA_URL##*/releases/tag/}" && \
    case "${HA_VERSION}" in ''|*[!A-Za-z0-9._+-]*) echo "No release tag in '${HA_URL}'" && exit 1 ;; esac && \
    echo "Installing Home Assistant CLI ${HA_VERSION} for ${HA_ARCH}..." && \
    curl -fsSL -o /usr/bin/ha \
        "https://github.com/home-assistant/cli/releases/download/${HA_VERSION}/ha_${HA_ARCH}" && \
    chmod +x /usr/bin/ha && \
    echo "Home Assistant CLI ${HA_VERSION} installed successfully"

# Install GitHub CLI (gh command), latest release; tag from the releases/latest
# redirect like the HA CLI above.
RUN case "$(cat /etc/addon-arch)" in \
        amd64)   GH_ARCH="amd64" ;; \
        aarch64) GH_ARCH="arm64" ;; \
        *)       echo "Unsupported architecture for gh: $(cat /etc/addon-arch)" && exit 1 ;; \
    esac && \
    echo "Fetching latest GitHub CLI version..." && \
    GH_URL=$(curl -fsSL -o /dev/null -w '%{url_effective}' https://github.com/cli/cli/releases/latest) && \
    GH_VERSION="${GH_URL##*/releases/tag/v}" && \
    case "${GH_VERSION}" in ''|*[!A-Za-z0-9._+-]*) echo "No release tag in '${GH_URL}'" && exit 1 ;; esac && \
    echo "Installing GitHub CLI v${GH_VERSION} for ${GH_ARCH}..." && \
    curl -fsSL -o /tmp/gh.tar.gz \
        "https://github.com/cli/cli/releases/download/v${GH_VERSION}/gh_${GH_VERSION}_linux_${GH_ARCH}.tar.gz" && \
    tar -xzf /tmp/gh.tar.gz -C /tmp && \
    mv "/tmp/gh_${GH_VERSION}_linux_${GH_ARCH}/bin/gh" /usr/bin/gh && \
    chmod +x /usr/bin/gh && \
    rm -rf /tmp/gh* && \
    echo "GitHub CLI v${GH_VERSION} installed successfully"

# Create directory for Claude configuration and set working directory
RUN mkdir -p /config/claude-config
WORKDIR /config

# Copy and install image service.
# `npm ci` installs exactly the committed lockfile, so two images built from the
# same add-on version get the same dependency tree. `npm install` resolved
# semver ranges at build time and could silently ship different code.
COPY image-service/ /opt/image-service/
WORKDIR /opt/image-service
RUN npm ci --omit=dev \
    && npm cache clean --force \
    && chmod +x server.js

# Back to the runtime working directory: the terminal opens in the Home
# Assistant configuration directory.
WORKDIR /config

# Copy startup script and modular scripts
COPY run.sh /run.sh
COPY scripts/ /opt/scripts/
COPY .claude/ /opt/.claude/
# claude-doctor: the startup health check, callable from the terminal
# (owine's fork, commit cc0d74e7); auto-continue: the runtime switch for
# auto-continue after a usage limit (mattbsea's fork, commit 00e22fc0)
RUN chmod +x /run.sh \
    && chmod +x /opt/scripts/*.sh \
    && ln -sf /opt/scripts/health-check.sh /usr/local/bin/claude-doctor \
    && ln -sf /opt/scripts/auto-continue.sh /usr/local/bin/auto-continue

# Use exec form for better signal handling
CMD ["/run.sh"]
