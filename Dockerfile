FROM node:24.16.0-bookworm-slim
ARG TARGETARCH=arm64

RUN apt-get update && apt-get install -y --no-install-recommends tmux git diffutils curl unzip ca-certificates python3 python3-pip wget gosu inotify-tools jq procps && \
    rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh 

# Install Azure CLI
RUN pip3 install azure-cli==2.87.0 --break-system-packages && rm -rf /root/.cache/pip

# Install PowerShell
RUN apt-get update && apt-get install -y --no-install-recommends wget tar ca-certificates libssl3 libicu72 && \
    wget -q "https://github.com/PowerShell/PowerShell/releases/download/v7.5.6/powershell-7.5.6-linux-${TARGETARCH}.tar.gz" -O /tmp/powershell.tar.gz && \
    mkdir -p /opt/microsoft/powershell/7 && \
    tar -xzf /tmp/powershell.tar.gz -C /opt/microsoft/powershell/7 && \
    chmod +x /opt/microsoft/powershell/7/pwsh && \
    ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/pwsh && \
    ln -sf /opt/microsoft/powershell/7/pwsh /usr/bin/powershell && \
    rm -rf /tmp/powershell* /var/lib/apt/lists/*

# Install npm packages
RUN npm install -g bun opencode-ai @colbymchenry/codegraph @agentmemory/agentmemory playwright-core @playwright/mcp @warp-dot-dev/opencode-warp

ENV WARP_CLI_AGENT_PROTOCOL_VERSION=1
ENV PLAYWRIGHT_BROWSERS_PATH=/ms-playwright

# Install Terraform
RUN curl -fsSL "https://releases.hashicorp.com/terraform/1.13.1/terraform_1.13.1_linux_${TARGETARCH}.zip" -o /tmp/terraform.zip && \
    unzip -q /tmp/terraform.zip -d /usr/local/bin/ && \
    rm /tmp/terraform.zip

# Install iii for agentmemory
RUN case "$TARGETARCH" in arm64) III_ARCH=iii-aarch64-unknown-linux-gnu;; amd64) III_ARCH=iii-x86_64-unknown-linux-gnu;; *) echo "Unsupported: $TARGETARCH" >&2 && exit 1;; esac && \
    curl -fsSL "https://github.com/iii-hq/iii/releases/download/iii/v0.11.2/${III_ARCH}.tar.gz" | tar -xz -C /usr/local/bin/

# Create omo user before installing other packages
RUN addgroup --gid 1001 omo && \
    adduser --uid 1001 --gid 1001 --shell /bin/bash --disabled-password --gecos "" omo

# Pre-create and own the Xenova transformers fallback cache dir (global pkg is root-owned)
RUN mkdir -p /usr/local/lib/node_modules/@agentmemory/agentmemory/node_modules/@xenova/transformers/.cache && \
    chown -R omo:omo /usr/local/lib/node_modules/@agentmemory/agentmemory/node_modules/@xenova/transformers/.cache

# Install chromium with dependencies for Playwright
RUN npx -y playwright-core install-deps chromium && \
    npx -y playwright-core install chromium && \
    CHROME_PATH=$(find /ms-playwright -maxdepth 3 -path '*/chrome-linux/chrome' -print -quit) && \
    [ -f "$CHROME_PATH" ] || { echo "Chromium not found"; exit 1; } && \
    mkdir -p /opt/google/chrome && ln -sf "$CHROME_PATH" /opt/google/chrome/chrome

# Switch to omo user for opencode config and runtime
USER omo
WORKDIR /home/omo

# Configure opencode
COPY --chown=omo:omo opencode.json /home/omo/.config/opencode/opencode.json
COPY --chown=omo:omo AGENTS.md /home/omo/.config/opencode/AGENTS.md

# Configure agentmemory
RUN mkdir -p /home/omo/.agentmemory
COPY --chown=omo:omo .env.agentmemory /home/omo/.agentmemory/.env
COPY --chown=omo:omo oh-my-openagent.jsonc /home/omo/.config/opencode/oh-my-openagent.jsonc

ENV AGENTMEMORY_III_CONFIG=/usr/local/lib/node_modules/@agentmemory/agentmemory/iii-config.docker.yaml
ENV AGENTMEMORY_VIEWER_HOST=0.0.0.0
ENV AGENTMEMORY_SECRET=omo
ENV VIEWER_ALLOWED_HOSTS=localhost:3113,127.0.0.1:3113,[::1]:3113

# Copy agentmemory opencode plugin and commands
RUN mkdir -p /home/omo/.config/opencode/plugins /home/omo/.config/opencode/commands && \
    cp /usr/local/lib/node_modules/@agentmemory/agentmemory/plugin/opencode/agentmemory-capture.ts /home/omo/.config/opencode/plugins/ && \
    cp /usr/local/lib/node_modules/@agentmemory/agentmemory/plugin/opencode/commands/recall.md /home/omo/.config/opencode/commands/ && \
    cp /usr/local/lib/node_modules/@agentmemory/agentmemory/plugin/opencode/commands/remember.md /home/omo/.config/opencode/commands/

# Register oh-my-openagent plugin with OpenCode (non-interactive)
RUN bunx oh-my-openagent install --no-tui --platform=opencode --claude=no --openai=no --gemini=no --copilot=no --skip-auth

# Install agentmemory skills
RUN npx -y skills add rohitg00/agentmemory -a opencode -y -s '*' -g

WORKDIR /home/omo/project

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
