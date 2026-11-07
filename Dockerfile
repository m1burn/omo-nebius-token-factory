# oh-my-openagent Nebius Token Factory Edition Docker image
#
# USAGE:
#   Build:
#     docker build -t omo .
#
#   Run (with the project folder shared):
#     docker run --name omo -d -v "$PWD:/home/omo/project" --restart unless-stopped omo
#
#   Start a new session with opencode:
#     docker exec -it omo opencode
#
#   This image includes both OpenCode, oh-my-openagent, agent memory and configuration for Nebius Token Factory pre-installed.
#
#   Tool versions: Terraform 1.13.1, Azure CLI 2.87.0, PowerShell 7.5.6
#

FROM node:24.16.0-bookworm-slim
ARG TARGETARCH=arm64

RUN apt-get update && apt-get install -y --no-install-recommends tmux git diffutils curl unzip ca-certificates python3 python3-pip wget gosu inotify-tools jq procps && \
    rm -rf /var/lib/apt/lists/*

COPY docker-entrypoint.sh /usr/local/bin/docker-entrypoint.sh
RUN chmod +x /usr/local/bin/docker-entrypoint.sh 

# Install Python
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
RUN npm install -g bun opencode-ai @colbymchenry/codegraph @agentmemory/agentmemory@0.9.27

# Install Terraform
RUN curl -fsSL "https://releases.hashicorp.com/terraform/1.13.1/terraform_1.13.1_linux_${TARGETARCH}.zip" -o /tmp/terraform.zip && \
    unzip -q /tmp/terraform.zip -d /usr/local/bin/ && \
    rm /tmp/terraform.zip

# Install iii for agentmemory
RUN case "$TARGETARCH" in arm64) III_ARCH=iii-aarch64-unknown-linux-gnu;; amd64) III_ARCH=iii-x86_64-unknown-linux-gnu;; *) echo "Unsupported: $TARGETARCH" >&2 && exit 1;; esac && \
    curl -fsSL "https://github.com/iii-hq/iii/releases/download/iii/v0.11.2/${III_ARCH}.tar.gz" | tar -xz -C /usr/local/bin/

# Create user before installing packages
RUN addgroup --gid 1001 omo && \
    adduser --uid 1001 --gid 1001 --shell /bin/bash --disabled-password --gecos "" omo

# Pre-create and own the Xenova transformers fallback cache dir (global pkg is root-owned)
RUN mkdir -p /usr/local/lib/node_modules/@agentmemory/agentmemory/node_modules/@xenova/transformers/.cache && \
    chown -R omo:omo /usr/local/lib/node_modules/@agentmemory/agentmemory/node_modules/@xenova/transformers/.cache

# Switch to user for OpenCode config and runtime
USER omo
WORKDIR /home/omo

# Configure agentmemory
RUN mkdir -p /home/omo/.agentmemory && \
    echo "OPENAI_BASE_URL=https://api.tokenfactory.us-central1.nebius.com/v1/" > /home/omo/.agentmemory/.env && \
    echo "OPENAI_MODEL=MiniMaxAI/MiniMax-M2.5" >> /home/omo/.agentmemory/.env && \
    echo "EMBEDDING_PROVIDER=local" >> /home/omo/.agentmemory/.env && \
    echo "AGENTMEMORY_AUTO_COMPRESS=true" >> /home/omo/.agentmemory/.env && \
    echo "AGENTMEMORY_INJECT_CONTEXT=true" >> /home/omo/.agentmemory/.env && \
    echo "GRAPH_EXTRACTION_ENABLED=true" >> /home/omo/.agentmemory/.env

# Copy agentmemory OpenCode plugin and commands
RUN mkdir -p /home/omo/.config/opencode/plugins /home/omo/.config/opencode/commands && \
    cp /usr/local/lib/node_modules/@agentmemory/agentmemory/plugin/opencode/agentmemory-capture.ts /home/omo/.config/opencode/plugins/ && \
    cp /usr/local/lib/node_modules/@agentmemory/agentmemory/plugin/opencode/commands/recall.md /home/omo/.config/opencode/commands/ && \
    cp /usr/local/lib/node_modules/@agentmemory/agentmemory/plugin/opencode/commands/remember.md /home/omo/.config/opencode/commands/

RUN echo '{"$schema":"https://opencode.ai/config.json","lsp":true,"model":"nebius/moonshotai/Kimi-K2.6","mcp":{"agentmemory":{"type":"local","command":["npx","-y","@agentmemory/mcp"]}},"provider":{"nebius":{"models":{"moonshotai/Kimi-K2.6":{"name":"Kimi-K2.6","family":"kimi","release_date":"2026-05-20","attachment":true,"reasoning":true,"tool_call":true,"temperature":true,"cost":{"input":0.95,"output":4},"limit":{"context":256000,"input":256000,"output":256000},"modalities":{"input":["text","image"],"output":["text"]},"interleaved":{"field":"reasoning_content"},"provider":{"api":"https://api.tokenfactory.us-central1.nebius.com/v1/"}},"zai-org/GLM-5.2":{"name":"GLM-5.2","family":"glm","release_date":"2026-06-17","attachment":false,"reasoning":true,"tool_call":true,"temperature":true,"cost":{"input":1.40,"output":4.40},"limit":{"context":436000,"input":436000,"output":436000},"modalities":{"input":["text"],"output":["text"]},"interleaved":{"field":"reasoning_content"}}}}}}' > /home/omo/.config/opencode/opencode.json

# Register oh-my-openagent plugin with OpenCode (non-interactive)
RUN bunx oh-my-openagent install --no-tui --platform=opencode \
  --claude=no --openai=no --gemini=no --copilot=no --skip-auth

RUN npx -y skills add rohitg00/agentmemory -a opencode -y -s '*' -g

# Configure oh-my-openagent with specified models
RUN echo '{"agents":{"sisyphus":{"model":"nebius/moonshotai/Kimi-K2.6"},"atlas":{"model":"nebius/moonshotai/Kimi-K2.6"},"oracle":{"model":"nebius/zai-org/GLM-5.2"},"explore":{"model":"nebius/moonshotai/Kimi-K2.6"},"librarian":{"model":"nebius/moonshotai/Kimi-K2.6"}},"categories":{"visual-engineering":{"model":"nebius/moonshotai/Kimi-K2.6"},"deep":{"model":"nebius/moonshotai/Kimi-K2.6"},"unspecified-high":{"model":"nebius/moonshotai/Kimi-K2.6"},"unspecified-low":{"model":"nebius/moonshotai/Kimi-K2.6"},"quick":{"model":"nebius/MiniMaxAI/MiniMax-M2.5"},"writing":{"model":"nebius/moonshotai/Kimi-K2.6"}}}' > /home/omo/.config/opencode/oh-my-openagent.jsonc

ENTRYPOINT ["/usr/local/bin/docker-entrypoint.sh"]
