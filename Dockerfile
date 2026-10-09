FROM node:24.16.0-bookworm-slim
ARG TARGETARCH=arm64

# Use bash with pipefail for every RUN so a failed stage mid-pipeline
# aborts the build instead of being masked
SHELL ["/bin/bash", "-o", "pipefail", "-c"]

RUN apt-get update && apt-get install -y --no-install-recommends tmux git diffutils curl unzip xz-utils ca-certificates python3 python3-pip gosu inotify-tools jq procps shellcheck && \
    rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh 

# Install Azure CLI and Python packages
ENV AZURE_CORE_COLLECT_TELEMETRY=false
RUN pip3 install --no-cache-dir --break-system-packages azure-cli==2.87.0 ruff yamllint && \
    rm -rf /root/.cache/pip

# Install PowerShell
ENV POWERSHELL_TELEMETRY_OPTOUT=1
RUN apt-get update && apt-get install -y --no-install-recommends tar ca-certificates libssl3 libicu72 && \
    curl -fsSL "https://github.com/PowerShell/PowerShell/releases/download/v7.5.6/powershell-7.5.6-linux-${TARGETARCH}.tar.gz" -o /tmp/powershell.tar.gz && \
    mkdir -p /opt/microsoft/powershell/7 && \
    tar -xzf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 && \
    chmod +x /opt/microsoft/powershell/7/pwsh && \
    ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh && \
    ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/powershell && \
    rm -rf /tmp/powershell* /var/lib/apt/lists/*

# Install PowerShell packages
RUN pwsh -NoProfile -Command "Set-PSRepository -Name PSGallery -InstallationPolicy Trusted; Install-Module PSScriptAnalyzer -Scope AllUsers -Force; Install-Module Pester -Scope AllUsers -Force"

# Install npm packages
RUN npm install -g bun opencode-ai @colbymchenry/codegraph @agentmemory/agentmemory playwright-core @playwright/mcp @warp-dot-dev/opencode-warp eslint typescript-eslint eslint-plugin-sonarjs jscpd knip markdownlint-cli2 && \
    npm cache clean --force

ENV WARP_CLI_AGENT_PROTOCOL_VERSION=1
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Install Terraform
RUN curl -fsSL "https://releases.hashicorp.com/terraform/1.13.1/terraform_1.13.1_linux_${TARGETARCH}.zip" -o /tmp/terraform.zip && \
    unzip -q /tmp/terraform.zip -d /usr/local/bin/ && \
    rm /tmp/terraform.zip

# Install .NET SDK
ENV DOTNET_CLI_TELEMETRY_OPTOUT=1 DOTNET_NOLOGO=1 NUGET_XMLDOC_MODE=skip
RUN curl -fsSL https://dot.net/v1/dotnet-install.sh -o /tmp/dotnet-install.sh && \
    bash /tmp/dotnet-install.sh --version latest --install-dir /usr/share/dotnet && \
    ln -sf /usr/share/dotnet/dotnet /usr/local/bin/dotnet && \
    rm -f /tmp/dotnet-install.sh

# Install iii for agentmemory.
RUN case "$TARGETARCH" in arm64) III_ARCH=iii-aarch64-unknown-linux-gnu;; amd64) III_ARCH=iii-x86_64-unknown-linux-gnu;; *) echo "Unsupported: $TARGETARCH" >&2 && exit 1;; esac && \
    curl -fsSL "https://github.com/iii-hq/iii/releases/download/iii/v0.22.1/${III_ARCH}.tar.gz" | tar -xz -C /usr/local/bin/

# Install tools from GitHub releases
# github_install <repo> <asset-pattern> <binary> <arm64-token> <amd64-token>
# Asset pattern tokens: {VER} = release tag without leading v, {ARCH} = per-arch token.
RUN set -eu; \
    github_install() { \
      repo="$1"; asset="$2"; member="$3"; \
      case "$TARGETARCH" in arm64) arch="$4";; amd64) arch="$5";; *) echo "Unsupported TARGETARCH: $TARGETARCH" >&2; exit 1;; esac; \
      tag=$(curl -sL -o /dev/null -w '%{url_effective}' "https://github.com/${repo}/releases/latest" | sed 's|.*/tag/||'); \
      name=$(printf '%s' "$asset" | sed -e "s/{VER}/${tag#v}/g" -e "s/{ARCH}/${arch}/g"); \
      pkg=$(mktemp); \
      curl -fsSL "https://github.com/${repo}/releases/download/${tag}/${name}" -o "$pkg"; \
      case "$name" in \
        *.tar.gz) tar -xzf "$pkg" -C /tmp "$member";; \
        *.zip) unzip -q "$pkg" "$member" -d /tmp;; \
        *) cp "$pkg" "/tmp/$member";; \
      esac; \
      install -m 0755 "/tmp/$member" "/usr/local/bin/$member"; \
      rm -f "$pkg" "/tmp/$member"; \
    }; \
    github_install hadolint/hadolint        'hadolint-Linux-{ARCH}'              hadolint arm64 x86_64; \
    github_install gitleaks/gitleaks        'gitleaks_{VER}_linux_{ARCH}.tar.gz' gitleaks arm64 x64; \
    github_install terraform-linters/tflint 'tflint_linux_{ARCH}.zip'            tflint   arm64 amd64; \
    github_install aquasecurity/trivy       'trivy_{VER}_Linux-{ARCH}.tar.gz'    trivy   ARM64 64bit

# Create omo user before installing other packages
RUN addgroup --gid 1001 omo && \
    adduser --uid 1001 --gid 1001 --shell /bin/bash --disabled-password --gecos "" omo

# Pre-create and own the Xenova transformers fallback cache dir (global pkg is root-owned)
RUN mkdir -p /usr/local/lib/node_modules/@agentmemory/agentmemory/node_modules/@xenova/transformers/.cache && \
    chown -R omo:omo /usr/local/lib/node_modules/@agentmemory/agentmemory/node_modules/@xenova/transformers/.cache

# Pre-create and own the Hugging Face transformers cache dir used by agentmemory v0.9.29+
RUN mkdir -p /usr/local/lib/node_modules/@agentmemory/agentmemory/node_modules/@huggingface/transformers/.cache && \
    chown -R omo:omo /usr/local/lib/node_modules/@agentmemory/agentmemory/node_modules/@huggingface/transformers/.cache

# Install chromium with dependencies for Playwright
WORKDIR /usr/local/lib/node_modules/@playwright/mcp
RUN npx --no-install playwright-core install-deps chromium && \
    npx --no-install playwright-core install chromium && \
    CHROME_PATH=$(find /ms-playwright -maxdepth 3 -path '*/chrome-linux*/chrome' -print -quit) && \
    [ -f "$CHROME_PATH" ] || { echo "Chromium not found"; exit 1; } && \
    mkdir -p /opt/google/chrome && ln -sf "$CHROME_PATH" /opt/google/chrome/chrome

# Bind-mounted /data/snapshots and /home/omo/project are host-owned, so git's
# CVE-2022-24765 safe-directory check must permit them.
RUN git config --system --add safe.directory /data/snapshots && \
    git config --system --add safe.directory /home/omo/project

# Switch to omo user for opencode config and runtime
USER 1001
WORKDIR /home/omo

# Configure opencode
COPY --chown=omo:omo opencode.json /home/omo/.config/opencode/opencode.json
COPY --chown=omo:omo AGENTS.md /home/omo/.config/opencode/AGENTS.md

RUN mkdir -p /home/omo/.omo
COPY --chown=omo:omo omo.jsonc /home/omo/.omo/omo.jsonc

# Configure agentmemory
RUN mkdir -p /home/omo/.agentmemory && \
    cp /usr/local/lib/node_modules/@agentmemory/agentmemory/iii-config.docker.yaml /home/omo/.agentmemory/iii-config.docker.yaml
COPY --chown=omo:omo agentmemory-housekeeper.sh /usr/local/bin/agentmemory_housekeeper
RUN chmod +x /usr/local/bin/agentmemory_housekeeper

# Copy agentmemory opencode plugin and commands
RUN mkdir -p /home/omo/.config/opencode/plugins /home/omo/.config/opencode/commands && \
    cp /usr/local/lib/node_modules/@agentmemory/agentmemory/plugin/opencode/agentmemory-capture.ts /home/omo/.config/opencode/plugins/ && \
    cp /usr/local/lib/node_modules/@agentmemory/agentmemory/plugin/opencode/commands/recall.md /home/omo/.config/opencode/commands/ && \
    cp /usr/local/lib/node_modules/@agentmemory/agentmemory/plugin/opencode/commands/remember.md /home/omo/.config/opencode/commands/

# Register oh-my-openagent with OpenCode and install agentmemory skills
RUN bunx oh-my-openagent install --no-tui --platform=opencode --claude=no --openai=no --gemini=no --copilot=no --skip-auth && \
    npx -y skills add rohitg00/agentmemory -a opencode -y -s '*' -g

# Configure quality gate
COPY --chown=omo:omo quality-gate/ /usr/local/bin/
RUN chmod +x /usr/local/bin/quality-gate.py
COPY --chown=omo:omo commands/quality-gate.md /home/omo/.config/opencode/commands/quality-gate.md

WORKDIR /home/omo/project

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
