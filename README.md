# oh-my-openagent - AI Development Environment

Docker-based development environment with pre-configured **OpenCode**,
**oh-my-openagent**, **agentmemory**, and **Nebius Token Factory**
integration.

## What is this project

This container provides a ready-to-use development environment for
AI-assisted software engineering. It includes:

- **OpenCode** — TUI coding agent for AI-assisted development
- **oh-my-openagent** — Enhanced agent framework with specialized agents
- **agentmemory** — Persistent memory across sessions with semantic
  search and knowledge graph
- **Nebius Token Factory** — Pre-configured with Kimi-K3, Kimi-K2.7-Code,
  GLM-5.3, GLM-5.3-Flash, DeepSeek-V4-Flash-0731, DeepSeek-V4.1-Flash,
  and MiniMax-M3 models

## Purpose

Provides a consistent, containerized environment for AI-driven
development workflows, enabling:

- Interactive code editing and refactoring
- Autonomous agent tasks with memory persistence
- Cross-session context continuity via agentmemory
- Browser automation via Playwright MCP
- Warp terminal integration through the OpenCode Warp plugin
- Seamless integration with Nebius Token Factory

### Security sandbox

The container acts as a **sandbox environment** with several important
properties:

- **Limited file access**: The container only has access to the project
  folder you mount at startup. It cannot read or modify files outside
  this directory.
- **Isolated from host**: No access to your host's authentication keys,
  SSH keys, environment variables, or other sensitive data unless you
  explicitly place them in the mounted project folder.
- **Controlled execution**: The agent can only modify files within the
  project folder. This prevents accidental execution of potentially
  destructive CLI commands (e.g., `terraform apply`,
  `az resource delete ...`, or other commands the agent might
  hallucinate as reasonable).

This design allows you to let the coding agent run autonomously while
minimizing risk of accidental damage to your system.

## Prerequisites

- Docker
- Nebius Token Factory API Key

## Getting Started

### Build and run with Docker Compose

This is the quickest path. The agent can only see the directory you
mount as the project folder, so replace `/path/to/your/project` with the
actual directory you want to work on.

> **Note:** Create a `.env.secrets` file in the
> `omo-nebius-token-factory` directory before running the command below.
> Docker Compose loads both `.env.agentmemory` (base configuration) and
> `.env.secrets` (user overrides). `.env.secrets` can be empty and is
> gitignored so it will not be committed:
>
> ```bash
> touch /path/to/omo-nebius-token-factory/.env.secrets
> ```
>
> You can add environment variables such as `EXA_API_KEY`,
> `OPENAI_API_KEY`, or `NEBIUS_API_KEY` to `.env.secrets` to override
> defaults.

```bash
cd /path/to/your/project
docker compose -f /path/to/omo-nebius-token-factory/docker-compose.yml up -d
```

The current directory (`/path/to/your/project`) is mounted as
`/home/omo/project` inside the container. This means:

- You can keep the `omo-nebius-token-factory` repository anywhere on
  your machine.
- Run the command above from whichever project folder you want the agent
  to edit.

This builds the `omo` image if it does not exist, persists agentmemory
data in `$HOME/.omo-agentmemory/data`, and publishes agentmemory
services on the host loopback: HTTP API on port 3111, stream endpoint on
port 3112, and the viewer dashboard on port 3113.

> **Note:** The `$HOME/.omo-agentmemory/data` volume mount persists
> agentmemory data (including snapshots and the state store) across
> container restarts, enabling cross-session memory continuity.

### Start a new opencode interactive session

```bash
docker exec -it -w /home/omo/project omo opencode
```

### View the agentmemory dashboard

Open [http://localhost:3113](http://localhost:3113) in your browser. The
first API call returns `401`, and the viewer shows an inline
authorization bar. Enter the `AGENTMEMORY_SECRET` value (default is
`omo`, set in `.env.agentmemory` and overridable via `.env.secrets`) and
click **Unlock**.

The viewer port is bound to the host loopback interface
(`127.0.0.1:3113`) so it cannot be reached from other machines on the
network.

### Enter your Nebius Token Factory API key

Add your Nebius Token Factory API key to `.env.secrets` before starting
the container:

```bash
# In /path/to/omo-nebius-token-factory/.env.secrets
OPENAI_API_KEY=your-nebius-token-factory-key
NEBIUS_API_KEY=your-nebius-token-factory-key
```

`docker-compose.yml` loads `.env.agentmemory` and `.env.secrets` into
the container environment, so both OpenCode and agentmemory use these
credentials automatically.

## Pre-installed tools

| Tool | Version |
| ---- | ------- |
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
| iii | 0.22.1 |

### Configured Models

- **Kimi-K3**: Main session model. Used by Sisyphus (and ultrawork),
  Atlas, Sisyphus-Junior, Multimodal-Looker, Prometheus, and Metis, plus
  the `visual-engineering`, `artistry`, and `writing` categories for
  planning, architecture, and high-context reasoning tasks.
- **GLM-5.3**: Used by Oracle, Momus, and the `ultrabrain`, `deep-low`,
  `deep-high`, and `unspecified-high` categories for complex reasoning,
  planning, and review tasks. Fastest strong reasoner on the platform
  (455 tok/s).
- **Kimi-K2.7-Code**: Used by the `unspecified-low` category as the
  catch-all worker — a fast (231 tok/s) code-specialized executor.
- **DeepSeek-V4-Flash-0731**: Used by Librarian, Explore, and the `quick`
  category for high-throughput search and simple tasks (351 tok/s).
- **MiniMax-M3**: Default model for agentmemory operations.

## Quality gates

Code quality is enforced by CLI analyzers **baked directly into the image**.

### Tool inventory

All tools are installed from their **latest available release** at image
build time, except where noted. Rebuild the image to pick up new
analyzer versions:

| Tool | Version | Covers |
| ---- | ------- | ------ |
| shellcheck | Debian package | Bash/shell scripts |
| hadolint | latest | Dockerfiles |
| gitleaks | latest | Secrets in any file |
| tflint | latest | Terraform HCL |
| trivy | latest | Terraform/IaC misconfigurations |
| ruff | latest | Python |
| yamllint | latest | YAML |
| eslint / typescript-eslint / eslint-plugin-sonarjs | latest | JS/TS/JSON |
| jscpd | latest | Copy-paste duplication (`--all` mode) |
| knip | latest | Dead code, unused exports and deps (`--all` mode) |
| markdownlint-cli2 | latest | Markdown |
| PSScriptAnalyzer | latest | PowerShell |
| Pester | latest | PowerShell tests |
| .NET SDK / SonarAnalyzer.CSharp / Roslynator.Analyzers | latest | C# |

Together these cover PowerShell, Bash, Python, JavaScript/TypeScript,
YAML, JSON-ish config files, Dockerfiles, Terraform, Markdown, and C# at
analyzer depth.

### Usage

Inside `opencode`:

- `/quality-gate` — opencode command that runs the gates, triages
  findings, applies minimal fixes, and re-checks.

### Configuration precedence

Your repository's own configs win when present (`eslint.config.js`,
`pyproject.toml`/`ruff.toml`, `.yamllint`, `.hadolint.yaml`,
`.gitleaks.toml`, ...). The defaults apply only when
the repo does not provide its own. The runner never creates or modifies
repo configs.
