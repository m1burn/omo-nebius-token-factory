# oh-my-openagent - AI Development Environment

Docker-based development environment with pre-configured **OpenCode**, **oh-my-openagent**, **agentmemory**, and **Nebius Token Factory** integration.

## What is this project

This container provides a ready-to-use development environment for AI-assisted software engineering. It includes:

- **OpenCode** — TUI coding agent for AI-assisted development
- **oh-my-openagent** — Enhanced agent framework with specialized agents
- **agentmemory** — Persistent memory across sessions with semantic search and knowledge graph
- **Nebius Token Factory** — Pre-configured with Kimi-K2.6, GLM-5.2, and MiniMax-M2.5 models

## Purpose

Provides a consistent, containerized environment for AI-driven development workflows, enabling:
- Interactive code editing and refactoring
- Autonomous agent tasks with memory persistence
- Cross-session context continuity via agentmemory
- Browser automation via Playwright MCP
- Seamless integration with Nebius Token Factory

### Security sandbox

The container acts as a **sandbox environment** with several important properties:

- **Limited file access**: The container only has access to the project folder you mount at startup. It cannot read or modify files outside this directory.
- **Isolated from host**: No access to your host's authentication keys, SSH keys, environment variables, or other sensitive data unless you explicitly place them in the mounted project folder.
- **Controlled execution**: The agent can only modify files within the project folder. This prevents accidental execution of potentially destructive CLI commands (e.g., `terraform apply`, `az resource delete ...`, or other commands the agent might hallucinate as reasonable).

This design allows you to let the coding agent run autonomously while minimizing risk of accidental damage to your system.

## Prerequisites

- Docker
- Nebius Token Factory API Key

## Getting Started

### Build the image

If you need to build the image yourself:

```bash
docker build -t omo .
```

### Important: Run from your project folder

The container mounts your current working directory as the project folder. **You must run it from the root of your project** — this is the only folder the container (and thus the AI agent) will have access to.

```bash
cd /path/to/your/project
docker run --name omo -d -v "$PWD:/home/omo/project" -v "$HOME/.omo-agentmemory:/home/omo/.omo-agentmemory" --restart unless-stopped omo
```

> **Note:** The second volume mount (`$HOME/.omo-agentmemory`) persists agentmemory data across container restarts, enabling cross-session memory continuity.

### Start a new opencode interactive session

```bash
docker exec -it -w /home/omo/project omo opencode
```

### Enter your Nebius Token Factory API key

When OpenCode starts for the first time, you need to enter your Nebius Token Factory API Key:

1. Type `/connect` and hit Enter, select Nebius as your provider
2. Enter your Nebius Token Factory API key, hit Enter
3. The key is automatically saved and applied for both opencode and agentmemory for persistent context

> **Note:** The container runs an auth watcher that automatically syncs the Nebius API key from OpenCode's auth storage to agentmemory, so both tools share the same credentials without manual configuration.


## Pre-installed tools

| Tool | Version |
|------|---------|
| Terraform | 1.13.1 |
| Azure CLI | 2.87.0 |
| PowerShell | 7.5.6 |
| Node.js | 24.16.0 |
| Bun | latest |
| OpenCode | latest |
| oh-my-openagent | latest |
| agentmemory | latest |
| codegraph | latest |
| Playwright + Chromium | latest |
| iii | 0.11.2 |

### Configured Models

- **Kimi-K2.6**: Primary model for most tasks (code editing, refactoring, exploration, writing)
- **GLM-5.2**: Used by the Oracle agent for complex reasoning tasks
- **MiniMax-M2.5**: Used for quick, simple tasks
