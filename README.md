# oh-my-openagent - AI Development Environment

Docker-based development environment with pre-configured **OpenCode**, **oh-my-openagent**, **agentmemory**, and **Nebius Token Factory** integration.

## What is this project

This container provides a ready-to-use development environment for AI-assisted software engineering. It includes:

- **OpenCode** — TUI coding agent for AI-assisted development
- **oh-my-openagent** — Enhanced agent framework with specialized agents
- **agentmemory** — Persistent memory across sessions with semantic search and knowledge graph
- **Nebius Token Factory** — Pre-configured with Kimi-K2.7-Code, Kimi-K2.6, GLM-5.2, and MiniMax-M3 models

## Purpose

Provides a consistent, containerized environment for AI-driven development workflows, enabling:
- Interactive code editing and refactoring
- Autonomous agent tasks with memory persistence
- Cross-session context continuity via agentmemory
- Browser automation via Playwright MCP
- Warp terminal integration through the OpenCode Warp plugin
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

### Build and run with Docker Compose

This is the quickest path. The agent can only see the directory you mount as the project folder, so replace `/path/to/your/project` with the actual directory you want to work on.

> **Note:** Create a `.env.secrets` file in the `omo-nebius-token-factory` directory before running the command below. Docker Compose references this file (it can be empty), and it is gitignored so it will not be committed:
> ```bash
> touch /path/to/omo-nebius-token-factory/.env.secrets
> ```
> You can add environment variables such as `AGENTMEMORY_SECRET` or `EXA_API_KEY` here to override defaults.

```bash
cd /path/to/your/project
docker compose -f /path/to/omo-nebius-token-factory/docker-compose.yml up -d
```

The current directory (`/path/to/your/project`) is mounted as `/home/omo/project` inside the container. This means:
- You can keep the `omo-nebius-token-factory` repository anywhere on your machine.
- Run the command above from whichever project folder you want the agent to edit.

This builds the `omo` image if it does not exist, persists agentmemory data in `$HOME/.omo-agentmemory/data`, and publishes agentmemory services on the host loopback: HTTP API on port 3111, stream endpoint on port 3112, and the viewer dashboard on port 3113.

> **Note:** The `$HOME/.omo-agentmemory/data` volume mount persists agentmemory data (including snapshots and the state store) across container restarts, enabling cross-session memory continuity.

### Start a new opencode interactive session

```bash
docker exec -it -w /home/omo/project omo opencode
```

### View the agentmemory dashboard

Open [http://localhost:3113](http://localhost:3113) in your browser. The first API call returns `401`, and the viewer shows an inline authorization bar. Enter the `AGENTMEMORY_SECRET` value (default is `omo`, set in the Dockerfile and overridable via `.env.secrets`) and click **Unlock**.

The viewer port is bound to the host loopback interface (`127.0.0.1:3113`) so it cannot be reached from other machines on the network.

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

- **Kimi-K2.7-Code**: Primary model for most tasks (code editing, refactoring, exploration, writing)
- **Kimi-K2.6**: Available configured model for general tasks
- **GLM-5.2**: Used by the Oracle, Metis, and Momus agents for complex reasoning, planning, and review tasks
- **MiniMax-M3**: Used by the Explore, Librarian, and Writing agents for quick, simple tasks
