# MasterConfig

Native macOS app for managing Claude Code sessions, agent orchestration, and multi-repo workflows.

## Zero-Defect Start Kit

Fresh Mac? Run this and you're done:

```bash
git clone https://github.com/ceelikonur/MasterConfig.git
cd MasterConfig
./setup.sh
```

### What `setup.sh` does

| Step | Command | What it does |
|------|---------|-------------|
| 1 | `npm install` | Installs MCP server dependencies |
| 2 | `claude mcp add orchestrator ...` | Registers orchestrator MCP with Claude |
| 3 | `mkdir ~/.claude/orchestrator/...` | Creates shared state directories |
| 4 | `xcodegen generate` | Generates .xcodeproj from project.yml |
| 5 | `xcodebuild` | Builds the app |
| 6 | `cp -R ... /Applications/` | Installs to /Applications |

### Prerequisites

Install these first (one-time):

```bash
# Homebrew
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

# Tools
brew install node xcodegen

# Claude Code
# https://claude.ai/claude-code — follow install instructions

# iTerm2 (required for orchestrator)
brew install --cask iterm2
```

### Manual Setup (if you prefer)

```bash
# 1. Clone & enter
git clone https://github.com/ceelikonur/MasterConfig.git
cd MasterConfig

# 2. MCP dependencies
cd MasterConfig/MCP && npm install && cd ../..

# 3. Register MCP server with Claude
claude mcp add orchestrator node "$(pwd)/MasterConfig/MCP/orchestrator-mcp-server.js"

# 4. Create state dirs
mkdir -p ~/.claude/orchestrator/messages
echo '[]' > ~/.claude/orchestrator/tasks.json

# 5. Build
xcodegen generate
xcodebuild -scheme MasterConfig -configuration Debug build

# 6. Install
cp -R ~/Library/Developer/Xcode/DerivedData/MasterConfig-*/Build/Products/Debug/MasterConfig.app /Applications/
```

## Architecture

### Orchestrator System

Agent'lar arası iletisim, shared file system + MCP uzerinden calisiyor:

```
MasterConfig UI
    │
    ▼ (task yazilir)
Lead Agent (iTerm window)
    │
    ▼ task_post (MCP tool)
~/.claude/orchestrator/tasks.json  ◄── shared task board
    │
    ▼ fs.watch (task-watcher.js)
Sub-Agent (iTerm tab)  ◄── TTY-based notification
    │
    ▼ task_update (MCP tool)
tasks.json updated
    │
    ▼ fs.watch
Lead Agent notified  ◄── TTY-based notification
```

**Key design decisions:**
- **No polling** — file watcher (`task-watcher.js`) monitors changes and notifies agents
- **TTY-based delivery** — Claude Code overrides iTerm session names, so we match by PID → TTY
- **Single-line notifications** — multi-line text triggers Claude Code paste mode
- **Shared filesystem** — each Claude instance has its own MCP server process, but all read/write the same `~/.claude/orchestrator/` files

### MCP Tools (orchestrator v3)

| Tool | Purpose |
|------|---------|
| `task_post` | Post task to shared board (assigns to agent) |
| `task_list` | List tasks (filter by assignee/status) |
| `task_update` | Update task status + result |
| `message_send` | Send direct message to agent |
| `message_read` | Read inbox messages |
| `team_info` | List all agents and their repos |

### File Structure

```
MasterConfig/
├── App/                        # SwiftUI app entry
├── Models/
│   ├── AppModels.swift         # Repo, settings models
│   └── OrchestratorModels.swift # Agent, task, state models
├── Services/
│   ├── OrchestratorService.swift # Team lifecycle, activation
│   └── TerminalService.swift     # iTerm AppleScript integration
├── Views/
│   └── Orchestrator/
│       ├── OrchestratorView.swift # Main orchestrator UI
│       ├── AgentCardView.swift    # Agent status cards
│       └── MessageLogView.swift   # Message feed
├── MCP/
│   ├── orchestrator-mcp-server.js # MCP server v3
│   ├── task-watcher.js            # File watcher for notifications
│   └── package.json
├── setup.sh                    # Zero-defect setup script
└── project.yml                 # XcodeGen spec
```

## Usage

1. Open MasterConfig
2. Go to **Orchestrator** tab
3. Click **New Team** → name it → Create
4. Click **Add Agent** → select repo → Spawn
5. Click **Activate** (bolt icon) → all agents start
6. Type task in the input field → Enter
7. Lead agent delegates to sub-agents automatically
8. Watch results flow in the Message Log
