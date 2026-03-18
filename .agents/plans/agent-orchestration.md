# Agent Orchestration System — Implementation Plan

> MasterConfig'e multi-repo agent team yönetimi eklenmesi
> Tarih: 2026-03-15

---

## Vizyon

Tek bir ana terminal session'dan konuşarak, farklı repo'lardaki Claude agent'ları yönetmek.
Agent'lar birbirleriyle MCP üzerinden iletişim kurabilir. App kapansa bile agent'lar çalışmaya
devam eder, app tekrar açılınca reconnect edilir.

```
Kullanıcı
    │
    ▼
Main Session (MasterConfig içi veya cmux)
    │  MCP: agent_spawn, agent_send, agent_read, agent_kill, agent_status
    │
    ├──► Agent: api-server    (cmux workspace, repo-a'da)
    ├──► Agent: web-app       (cmux workspace, repo-b'de)
    └──► Agent: shared-lib    (cmux workspace, repo-c'de)
         ▲          ▲
         └──────────┘  (MCP: agent_send ile birbirine mesaj atar)
```

---

## Mimari Kararlar

| Karar | Seçim | Gerekçe |
|-------|-------|---------|
| Agent arası iletişim | MCP Server | Claude native MCP desteği, structured tool calls |
| Main session konumu | Hem embedded hem cmux | Kullanıcı tercihine bırak |
| Agent persistence | Background + reconnect | cmux workspace'ler zaten persist ediyor |
| Message format | JSON dosyalar | Basit, debug edilebilir, file watcher ile reactive |
| State storage | ~/.claude/orchestrator/ | Merkezi, app-agnostic |

---

## Dosya Yapısı (Yeni)

```
MasterConfig/
├── Services/
│   ├── TerminalService.swift          (mevcut — güncellenir)
│   ├── OrchestratorService.swift      (YENİ — agent lifecycle, message bus)
│   └── MCPHostService.swift           (YENİ — embedded MCP server)
├── Models/
│   ├── AppModels.swift                (mevcut — NavSection'a .orchestrator eklenir)
│   └── OrchestratorModels.swift       (YENİ — AgentInstance, AgentMessage, TeamConfig)
├── Views/
│   ├── Chat/
│   │   └── ChatView.swift             (mevcut — güncellenir)
│   └── Orchestrator/
│       ├── OrchestratorView.swift     (YENİ — ana view: terminal + dashboard)
│       ├── AgentCardView.swift        (YENİ — agent durum kartı)
│       ├── MessageLogView.swift       (YENİ — agent arası mesaj log'u)
│       └── EmbeddedTerminalView.swift (YENİ — in-app terminal emulator)
└── MCP/
    └── orchestrator-mcp-server.js     (YENİ — Node.js MCP server binary)

~/.claude/orchestrator/                (Runtime state — app dışında persist)
├── state.json                         (aktif agent'lar, team config)
├── messages/
│   ├── {agent-id}/inbox.jsonl         (gelen mesajlar)
│   └── {agent-id}/outbox.jsonl        (giden mesajlar)
└── logs/
    └── {session-timestamp}.log        (orchestrator log)
```

---

## Fazlar

### Faz 1: Temel Modeller + OrchestratorService
**Dosyalar:** `OrchestratorModels.swift`, `OrchestratorService.swift`
**Bağımlılık:** Yok

#### 1.1 OrchestratorModels.swift

```swift
// Bir agent instance'ı (cmux workspace'te çalışan Claude session)
struct AgentInstance: Identifiable, Codable, Sendable {
    let id: UUID
    var name: String                    // "api-server"
    var repoPath: String               // "/Users/onur/Desktop/api-server"
    var repoName: String               // "api-server"
    var cmuxWorkspaceRef: String       // cmux UUID
    var status: AgentStatus
    var currentTask: String?           // şu an ne yapıyor
    var spawnedAt: Date
    var lastActivity: Date
    var messageCount: Int
}

enum AgentStatus: String, Codable, Sendable {
    case starting    // cmux workspace açılıyor
    case idle        // bekliyor
    case working     // aktif çalışıyor
    case blocked     // başka agent'ı bekliyor
    case completed   // işi bitti
    case dead        // workspace kapanmış
    case orphan      // app kapanmış ama workspace hala açık
}

// Agent'lar arası mesaj
struct AgentMessage: Identifiable, Codable, Sendable {
    let id: UUID
    let timestamp: Date
    let from: String                   // agent name veya "orchestrator"
    let to: String                     // agent name veya "orchestrator" veya "broadcast"
    let content: String
    let messageType: MessageType

    enum MessageType: String, Codable, Sendable {
        case task           // iş ataması
        case result         // iş sonucu
        case context        // bağlam paylaşımı
        case question       // soru
        case status         // durum güncellemesi
        case shutdown       // kapatma talebi
    }
}

// Orchestrator session state (persist edilir)
struct OrchestratorState: Codable, Sendable {
    var sessionId: UUID
    var teamName: String
    var agents: [AgentInstance]
    var mainSessionMode: MainSessionMode   // embedded veya cmux
    var mainSessionRef: String?            // cmux workspace ref (cmux modunda)
    var createdAt: Date
    var lastSaved: Date

    enum MainSessionMode: String, Codable, Sendable {
        case embedded   // MasterConfig içi terminal
        case cmux       // cmux workspace
    }
}
```

#### 1.2 OrchestratorService.swift

```swift
@Observable @MainActor
final class OrchestratorService {
    var state: OrchestratorState?
    var messages: [AgentMessage] = []       // tüm mesaj log'u
    var isRunning: Bool = false

    private let stateDir: URL               // ~/.claude/orchestrator/
    private let messagesDir: URL            // ~/.claude/orchestrator/messages/
    private let terminalService: TerminalService

    // -- Lifecycle --
    func startTeam(name: String, mode: MainSessionMode) async
    func resumeTeam() async                 // app açılınca mevcut state'i yükle
    func shutdownTeam() async               // tüm agent'ları kapat

    // -- Agent Management --
    func spawnAgent(name: String, repoPath: String, task: String?) async -> AgentInstance
    func killAgent(_ agentId: UUID) async
    func getAgentOutput(_ agentId: UUID) async -> String   // cmux read-screen

    // -- Messaging --
    func sendMessage(from: String, to: String, content: String, type: MessageType) async
    func broadcastMessage(from: String, content: String) async
    func pollMessages(for agentName: String) -> [AgentMessage]

    // -- Status --
    func refreshAllStatus() async           // tüm agent'ların cmux durumunu kontrol et
    func reconnectOrphans() async           // app açılınca orphan agent'ları bul

    // -- Persistence --
    func saveState() async                  // state.json'a yaz
    func loadState() async -> OrchestratorState?  // state.json'dan oku
}
```

**Temel davranışlar:**

- `spawnAgent()`: TerminalService üzerinden cmux workspace açar, Claude'u başlatır,
  Claude'a MCP server config'ini inject eder (env variable veya --mcp-config ile)
- `resumeTeam()`: App açılınca `state.json` okur, her agent'ın cmux workspace'inin
  hala aktif olup olmadığını kontrol eder, aktif olanları reconnect eder
- `saveState()`: Her değişiklikte `~/.claude/orchestrator/state.json`'a yazar
- Mesajlar `~/.claude/orchestrator/messages/{agent-id}/inbox.jsonl` formatında

---

### Faz 2: MCP Server (orchestrator-mcp-server)
**Dosyalar:** `MCP/orchestrator-mcp-server.js`, MCP config entegrasyonu
**Bağımlılık:** Faz 1

MasterConfig'in barındırdığı bir MCP server. Her Claude session (main + sub-agent'lar)
bu server'a bağlanır.

#### 2.1 MCP Tool Tanımları

```
Tool: agent_spawn
  Input:  { name: string, repo_path: string, task?: string }
  Output: { agent_id: string, status: "started" }
  Desc:   Yeni bir agent başlat. Belirtilen repo'da Claude session açar.

Tool: agent_send
  Input:  { to: string, message: string, type?: "task"|"context"|"question" }
  Output: { delivered: true, message_id: string }
  Desc:   Bir agent'a mesaj gönder. "to" agent adı veya "broadcast".

Tool: agent_read
  Input:  { agent_name: string, lines?: number }
  Output: { output: string, status: string }
  Desc:   Bir agent'ın terminal çıktısını oku.

Tool: agent_status
  Input:  {}
  Output: { agents: [{ name, status, repo, current_task, last_activity }] }
  Desc:   Tüm aktif agent'ların durumunu göster.

Tool: agent_kill
  Input:  { agent_name: string }
  Output: { killed: true }
  Desc:   Bir agent'ı kapat.

Tool: agent_list_messages
  Input:  { agent_name?: string, limit?: number }
  Output: { messages: [{ from, to, content, timestamp, type }] }
  Desc:   Mesaj log'unu göster. agent_name verilirse sadece o agent'ın mesajları.
```

#### 2.2 MCP Server Implementasyonu

İki seçenek:

**Seçenek A: Standalone Node.js MCP Server (önerilen)**
- `orchestrator-mcp-server.js` — stdio-based MCP server
- `~/.claude/orchestrator/` dizinindeki dosyaları okur/yazar
- Agent spawn/kill işlemleri için cmux binary'sini çağırır
- Her Claude session bu MCP server'ı kullanacak şekilde config edilir

**Seçenek B: Swift-native MCP Server (MasterConfig içinde)**
- MasterConfig process'i içinde çalışır
- Unix socket üzerinden iletişim
- App kapanınca MCP server da kapanır (dezavantaj)

→ **Seçenek A** daha iyi çünkü:
  - App kapansa bile agent'lar MCP server'a erişebilir
  - Claude CLI zaten stdio MCP server'ları destekliyor
  - Node.js MCP SDK (@modelcontextprotocol/sdk) olgun ve stabil

#### 2.3 MCP Server'ın Agent'lara Inject Edilmesi

Her agent spawn edilirken Claude'a şu şekilde MCP server bağlanır:

```bash
claude --mcp-config /tmp/masterconfig-agent-{id}.json --dangerously-skip-permissions
```

Veya `~/.claude.json`'a global olarak eklenir (tüm session'lar otomatik erişir).

**Global ekleme yaklaşımı (daha temiz):**
```json
{
  "mcpServers": {
    "orchestrator": {
      "command": "node",
      "args": ["~/.claude/orchestrator/mcp-server.js"],
      "env": {
        "ORCHESTRATOR_STATE_DIR": "~/.claude/orchestrator"
      }
    }
  }
}
```

---

### Faz 3: Main Session — Embedded Terminal
**Dosyalar:** `EmbeddedTerminalView.swift`, `OrchestratorView.swift`
**Bağımlılık:** Faz 1, 2

#### 3.1 EmbeddedTerminalView

SwiftUI içinde basit bir terminal emulator:
- Claude CLI'ı bir `Process` olarak başlat
- stdin/stdout/stderr pipe'larını yönet
- Pseudo-terminal (PTY) aç (ANSI escape sequence desteği için)
- Kullanıcı input'unu stdin'e yaz
- stdout'u monospace text olarak göster

```swift
struct EmbeddedTerminalView: View {
    @State private var outputText: String = ""
    @State private var inputText: String = ""
    let process: Process
    let inputPipe: Pipe

    var body: some View {
        VStack(spacing: 0) {
            // Terminal output — scrollable, monospace
            ScrollViewReader { proxy in
                ScrollView {
                    Text(outputText)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id("bottom")
                }
                .onChange(of: outputText) { proxy.scrollTo("bottom") }
            }

            Divider()

            // Input bar
            HStack {
                TextField("Message...", text: $inputText)
                    .textFieldStyle(.plain)
                    .font(.system(.body, design: .monospaced))
                    .onSubmit { sendInput() }

                Button("Send") { sendInput() }
            }
            .padding(8)
        }
    }
}
```

**PTY yaklaşımı** (daha iyi terminal deneyimi):
- `forkpty()` veya `posix_openpt()` kullanarak pseudo-terminal aç
- Bu sayede Claude CLI tam terminal modunda çalışır
- ANSI renkleri ve cursor hareketleri desteklenir
- SwiftTerm kütüphanesi kullanılabilir (açık kaynak terminal emulator)

#### 3.2 OrchestratorView (Ana Orchestrator Ekranı)

```
┌──────────────────────────────────────────────────────┐
│  Orchestrator                          [cmux] [⚙️]   │
├──────────┬───────────────────────────────────────────┤
│ Agents   │                                           │
│          │  ┌─────────────────────────────────────┐  │
│ ● main   │  │  Main Terminal (embedded/cmux)      │  │
│           │  │  > web-app ve api-server'daki       │  │
│ ── team ──│  │    auth'u senkronize et             │  │
│ ● api    │  │                                     │  │
│   working │  │  Claude: 2 agent spawn ediyorum... │  │
│ ● web    │  │  ✓ agent "api-server" started       │  │
│   idle   │  │  ✓ agent "web-app" started          │  │
│          │  │  ...                                │  │
│          │  └─────────────────────────────────────┘  │
│          │                                           │
│          │  ┌─────────────────────────────────────┐  │
│          │  │ Agent Activity                      │  │
│          │  │ ┌─────────┐ ┌─────────┐            │  │
│          │  │ │api-serv │ │web-app  │            │  │
│          │  │ │⏳working │ │💤idle    │            │  │
│          │  │ │auth fix │ │waiting  │            │  │
│          │  │ └─────────┘ └─────────┘            │  │
│          │  └─────────────────────────────────────┘  │
│          │                                           │
│          │  ┌─────────────────────────────────────┐  │
│          │  │ Message Log                         │  │
│          │  │ 14:32 orchestrator → api-server:    │  │
│          │  │   "auth endpoint'i JWT'ye çevir"    │  │
│          │  │ 14:33 api-server → web-app:         │  │
│          │  │   "yeni auth response format: ..."  │  │
│          │  │ 14:35 web-app → orchestrator:       │  │
│          │  │   "login flow güncellendi"          │  │
│          │  └─────────────────────────────────────┘  │
└──────────┴───────────────────────────────────────────┘
```

**Layout:**
- Sol sidebar: agent listesi (status indicator ile)
- Sağ üst: Main terminal (embedded veya cmux preview)
- Sağ orta: Agent kartları (grid, tıklanınca agent output açılır)
- Sağ alt: Message log (kronolojik, filtrelenebilir)

---

### Faz 4: Agent CLAUDE.md Injection
**Dosyalar:** OrchestratorService'e ekleme
**Bağımlılık:** Faz 2

Her sub-agent spawn edilirken, o agent'ın Claude session'ına özel talimatlar verilir.
Bu, agent'ın reposundaki `.claude/CLAUDE.md`'ye geçici olarak veya `--system-prompt`
flag'i ile inject edilir.

#### 4.1 Agent System Prompt Template

```markdown
# Agent Role: {agent_name}
You are part of a coordinated agent team managed by an orchestrator.

## Your Identity
- Name: {agent_name}
- Repo: {repo_path}
- Team: {team_name}
- Role: Worker agent for {repo_name}

## Communication
You have access to the `orchestrator` MCP server with these tools:
- `agent_send(to, message, type)` — Send message to another agent or orchestrator
- `agent_status()` — Check status of all team members
- `agent_list_messages(agent_name)` — Read messages

## Rules
1. When you complete a task, send a result message to the orchestrator
2. If you need information from another repo, use agent_send to ask that agent
3. If you're blocked, set your status to "blocked" and explain why
4. Never modify files outside your repo ({repo_path})
5. Report progress regularly via agent_send to orchestrator
```

#### 4.2 Injection Stratejisi

```swift
func spawnAgent(name: String, repoPath: String, task: String?) async -> AgentInstance {
    // 1. Agent system prompt oluştur
    let prompt = generateAgentPrompt(name: name, repoPath: repoPath)

    // 2. Geçici prompt dosyası yaz
    let promptFile = "/tmp/masterconfig-agent-\(name).md"
    try prompt.write(toFile: promptFile, atomically: true, encoding: .utf8)

    // 3. Claude'u bu prompt ile başlat
    let claudeCmd = "\(claudePath) --dangerously-skip-permissions --system-prompt \(promptFile)"
    // Alternatif: ilk mesaj olarak prompt'u gönder
    // let claudeCmd = "echo '\(prompt)' | \(claudePath) --dangerously-skip-permissions"

    // 4. cmux workspace aç
    let shellCmd = "cd \(repoPath.shellEscaped) && \(claudeCmd)"
    let ref = await terminalService.openInCmux(title: "Agent: \(name)", command: shellCmd)

    // 5. İlk task varsa gönder
    if let task = task {
        await sendMessage(from: "orchestrator", to: name, content: task, type: .task)
    }
}
```

---

### Faz 5: Reconnect & Persistence
**Dosyalar:** OrchestratorService güncelleme
**Bağımlılık:** Faz 1, 2

#### 5.1 State Persistence

Her state değişikliğinde `~/.claude/orchestrator/state.json` güncellenir:

```json
{
  "sessionId": "uuid",
  "teamName": "auth-refactor",
  "agents": [
    {
      "id": "uuid",
      "name": "api-server",
      "repoPath": "/Users/onur/Desktop/api-server",
      "cmuxWorkspaceRef": "cmux-uuid",
      "status": "working",
      "currentTask": "auth endpoint JWT migration",
      "spawnedAt": "2026-03-15T14:30:00Z",
      "lastActivity": "2026-03-15T14:35:00Z"
    }
  ],
  "mainSessionMode": "embedded",
  "createdAt": "2026-03-15T14:30:00Z",
  "lastSaved": "2026-03-15T14:35:00Z"
}
```

#### 5.2 App Başlangıcında Reconnect

```swift
// MasterConfigApp.swift — onAppear
func reconnect() async {
    guard let state = await orchestratorService.loadState() else { return }

    // cmux'taki aktif workspace'leri al
    let activeRefs = await TerminalService.listCmuxWorkspaceRefs()

    for agent in state.agents {
        if activeRefs.contains(agent.cmuxWorkspaceRef) {
            // Agent hala çalışıyor — reconnect
            agent.status = .idle  // veya mevcut durumunu koru
        } else {
            // Agent'ın workspace'i kapanmış
            agent.status = .dead
        }
    }

    orchestratorService.state = state
    orchestratorService.isRunning = state.agents.contains { $0.status != .dead }
}
```

#### 5.3 FileWatcher ile Reactive Updates

Message dizinini izle — yeni mesaj geldiğinde UI otomatik güncellenir:

```swift
fileWatcher.watch("~/.claude/orchestrator/messages/") {
    orchestratorService.reloadMessages()
}
```

---

### Faz 6: NavSection + ContentView Entegrasyonu
**Dosyalar:** `AppModels.swift`, `ContentView.swift`
**Bağımlılık:** Faz 3

```swift
// AppModels.swift — NavSection'a ekle
case orchestrator = "Orchestrator"

var icon: String {
    case .orchestrator: return "network"
}

// ContentView.swift — detailView'a ekle
case .orchestrator:
    OrchestratorView()
```

---

## Uygulama Sırası

```
Faz 1 ──► Faz 2 ──► Faz 4
                 ├──► Faz 3 ──► Faz 6
                 └──► Faz 5
```

- Faz 1 + 2 temeldir, önce bunlar yapılır
- Faz 3, 4, 5 paralel gidebilir
- Faz 6 en son, her şey hazır olunca entegrasyon

## Tahmini Dosya Sayısı

| Dosya | Durum | Satır (yaklaşık) |
|-------|-------|-------------------|
| OrchestratorModels.swift | YENİ | ~80 |
| OrchestratorService.swift | YENİ | ~350 |
| orchestrator-mcp-server.js | YENİ | ~250 |
| OrchestratorView.swift | YENİ | ~400 |
| AgentCardView.swift | YENİ | ~120 |
| MessageLogView.swift | YENİ | ~150 |
| EmbeddedTerminalView.swift | YENİ | ~200 |
| AppModels.swift | GÜNCELLE | +5 |
| ContentView.swift | GÜNCELLE | +5 |
| TerminalService.swift | GÜNCELLE | +30 |
| MasterConfigApp.swift | GÜNCELLE | +10 |
| **Toplam** | | **~1600** |

## Riskler & Dikkat Edilecekler

1. **PTY/Terminal Emulation**: Embedded terminal için SwiftTerm veya custom PTY gerekebilir.
   Basit başla (pipe-based), sonra PTY'ye geç.

2. **MCP Server Lifecycle**: Node.js MCP server'ın her zaman çalışır durumda olması lazım.
   LaunchAgent olarak kaydetmek bir seçenek.

3. **Message Delivery**: Dosya-tabanlı mesajlaşma polling gerektirir. FileWatcher ile
   çözülebilir ama race condition'lara dikkat.

4. **Claude CLI flags**: `--system-prompt` veya `--mcp-config` flag'lerinin mevcut
   Claude CLI sürümünde desteklenip desteklenmediğini kontrol et.

5. **Concurrent File Access**: Birden fazla agent aynı anda state.json'a yazarsa sorun
   olabilir. Agent'lar sadece kendi inbox/outbox'larına yazsın, state.json'u sadece
   OrchestratorService güncellesin.
