# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Run

```bash
# One-command launch (recommended for development)
chmod +x run.sh && ./run.sh

# Build the main server binary
go build -o cyberstrike-ai cmd/server/main.go

# Run directly
go run cmd/server/main.go
# With explicit config path
go run cmd/server/main.go --config config.yaml

# Build MCP stdio binary (for Cursor/CLI integration)
go build -o cyberstrike-ai-mcp cmd/mcp-stdio/main.go

# Run tests
go test ./...
# Run a single package's tests
go test ./internal/agent/...
go test ./internal/security/...
```

## Architecture Overview

CyberStrikeAI is a Go web server (`github.com/gin-gonic/gin`) exposing an AI-driven security testing platform. The entry point is `cmd/server/main.go`, which loads `config.yaml`, then delegates to `internal/app/app.go` which wires all subsystems together.

### Core Data Flow

```
User/Web UI → Gin HTTP router → handler/* → agent.Agent → MCP Server → security.Executor → Tool execution
```

1. **`internal/agent/agent.go`** — The AI agent loop. Sends user messages to an OpenAI-compatible LLM, receives tool-call responses, executes them via the MCP server, and iterates until completion. Manages conversation history and memory compression (`memory_compressor.go`).

2. **`internal/mcp/`** — MCP (Model Context Protocol) server implementation. `server.go` registers tools and dispatches calls; `external_manager.go` manages federated external MCP servers (HTTP/stdio/SSE transports). Tools exposed to the AI are registered here.

3. **`internal/security/executor.go`** — Executes security tool commands from YAML definitions in `tools/*.yaml`. Handles large-result pagination (>200KB stored as artifacts in `tmp/`), result compression, and timeouts. Tools are registered into the MCP server.

4. **`internal/handler/`** — Gin HTTP handlers, one file per domain: `agent.go` (AI loop + batch tasks), `conversation.go`, `monitor.go` (tool execution logs), `vulnerability.go`, `role.go`, `skills.go`, `knowledge.go`, `external_mcp.go`, `attackchain.go`, `robot.go` (DingTalk/Lark/WeCom), `config.go` (live config apply), etc.

5. **`internal/database/`** — SQLite persistence via `mattn/go-sqlite3`. Stores conversations, tool executions, vulnerabilities, batch task queues, and optionally a separate `knowledge.db`.

6. **`internal/knowledge/`** — Vector search knowledge base. `manager.go` scans `knowledge_base/` Markdown files, `indexer.go` builds embeddings (OpenAI API), `retriever.go` does hybrid vector+keyword search. Registered as `search_knowledge_base` MCP tool.

7. **`internal/skills/`** — Loads `skills/*/SKILL.md` files. Registered as `list_skills` / `read_skill` MCP tools so the AI can access skill content on-demand.

8. **`internal/robot/`** — Long-lived streaming connections for DingTalk and Lark (Feishu) chatbots. Started/restarted without server restart via `app.RestartRobotConnections()`.

9. **`internal/app/app.go`** — The composition root. Initializes all subsystems, wires dependencies, registers MCP tools (including the built-in `record_vulnerability` tool inline), and sets up Gin routes via `setupRoutes()`.

### Key Configuration

`config.yaml` controls everything: OpenAI API credentials (`openai.*`), server/MCP ports, tool directory (`security.tools_dir`), roles directory (`roles_dir`), skills directory (`skills_dir`), knowledge base (`knowledge.*`), and chatbot credentials (`robots.*`).

### Extension Points

- **Add a tool**: Create `tools/<name>.yaml` with `name`, `command`, `args`, `parameters[]`, and `description`. No code changes needed.
- **Add a role**: Create `roles/<name>.yaml` with `name`, `description`, `user_prompt`, `tools[]`, `skills[]`, `enabled`. No code changes needed.
- **Add a skill**: Create `skills/<name>/SKILL.md`. Attach to roles via their YAML `skills` field.
- **Add a knowledge item**: Place `.md` files in `knowledge_base/<category>/`. Scan and index via web UI or API (`POST /api/knowledge/scan`).

### MCP Transports

- **HTTP MCP**: Auto-started on `mcp.port` (default 8081) when `mcp.enabled: true`
- **stdio MCP**: `cmd/mcp-stdio/main.go` for Cursor/CLI integration
- **External MCP federation**: Managed via `internal/mcp/external_manager.go`, configured through `/api/external-mcp` endpoints
