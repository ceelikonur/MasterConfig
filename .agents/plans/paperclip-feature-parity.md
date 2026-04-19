# Paperclip Feature Parity — Implementation Plan
> Source: https://github.com/paperclipai/paperclip
> Target: MasterConfig (native macOS SwiftUI app)
> Created: 2026-03-29 | Status: Draft

---

## Overview

MasterConfig'e Paperclip'in temel özelliklerini adapte ediyoruz. Paperclip web-based (React + PostgreSQL), biz native SwiftUI + JSON/file-based. Her özelliği kendi mimarimize uygun şekilde implemente edeceğiz.

**Temel Fark:** Paperclip PostgreSQL kullanıyor, biz JSON dosyaları ile çalışıyoruz. Bu yüzden her feature'ı file-based architecture'a adapte edeceğiz.

---

## Phase 1: Hiyerarşik Task Sistemi (YÜKSEK ÖNCELİK)

### 1.1 — Veri Modeli Genişletme
**Dosya:** `MasterConfig/Models/AppModels.swift`

Mevcut `OrcTask` modeli çok basit. Şu hiyerarşiyi ekle:

```
Goal (Initiative)
  └── Project
       └── Milestone
            └── Issue (mevcut Task'ın genişletilmişi)
                 └── Sub-issue
```

**Yeni Model Yapısı:**
```swift
struct TaskHierarchy: Codable {
    var goals: [Goal]
}

struct Goal: Codable, Identifiable {
    let id: String          // UUID
    var title: String
    var description: String
    var status: GoalStatus  // active, completed, archived
    var projects: [String]  // project ID'leri
    var createdAt: Date
    var updatedAt: Date
}

struct Project: Codable, Identifiable {
    let id: String
    var title: String
    var description: String
    var goalId: String?     // parent goal
    var milestones: [String]
    var status: ProjectStatus
    var budget: BudgetConfig?
    var createdAt: Date
}

struct Milestone: Codable, Identifiable {
    let id: String
    var title: String
    var projectId: String
    var issues: [String]
    var dueDate: Date?
    var status: MilestoneStatus // open, closed
}

// Mevcut OrcTask'ı genişlet:
struct Issue: Codable, Identifiable {
    let id: String
    var title: String
    var description: String
    var milestoneId: String?
    var projectId: String?
    var parentIssueId: String?  // sub-issue desteği
    var assignee: String?
    var status: IssueStatus     // backlog, todo, in_progress, review, done
    var priority: IssuePriority // low, normal, high, urgent
    var labels: [String]
    var comments: [Comment]
    var attachments: [String]   // dosya yolları
    var createdBy: String
    var createdAt: Date
    var updatedAt: Date
}

struct Comment: Codable, Identifiable {
    let id: String
    var author: String
    var body: String
    var createdAt: Date
}
```

**Dosya Yapısı:**
```
~/.claude/orchestrator/
├── hierarchy.json          // Goal → Project → Milestone mapping
├── projects/
│   ├── <project-id>.json   // Project detayları
│   └── ...
├── issues/
│   ├── <issue-id>.json     // Issue detayları
│   └── ...
└── tasks.json              // Mevcut (backward compat)
```

### 1.2 — Task View Yeniden Tasarımı
**Dosya:** `MasterConfig/Views/Tasks/TasksView.swift`

Mevcut flat task list'i hiyerarşik görünüme dönüştür:

- **Sol panel:** Goal → Project → Milestone ağaç yapısı (OutlineGroup)
- **Orta panel:** Seçili milestone/project'in issue'ları (Kanban veya Liste)
- **Sağ panel:** Seçili issue'nun detayları + comments
- **Kanban modu:** Sürükle-bırak ile status değiştirme (backlog → todo → in_progress → review → done)
- **Filtreler:** Assignee, priority, label, status bazlı filtreleme
- **Quick-add:** Cmd+N ile yeni issue oluştur

### 1.3 — MCP Server Güncelleme
**Dosya:** `MasterConfig/MCP/orchestrator-mcp-server.js`

Mevcut `task_post`, `task_list`, `task_update` tool'larını genişlet:

```javascript
// Yeni tool'lar:
- goal_create(title, description)
- goal_list(status?)
- project_create(title, description, goalId?)
- project_list(goalId?, status?)
- milestone_create(title, projectId, dueDate?)
- issue_create(title, description, projectId?, milestoneId?, assignee?, priority?, labels?)
- issue_update(id, fields...)
- issue_comment(issueId, author, body)
- issue_list(projectId?, milestoneId?, assignee?, status?, priority?)

// Mevcut tool'lar backward-compatible kalmalı
- task_post → issue_create'e proxy olmalı
- task_list → issue_list'e proxy olmalı
- task_update → issue_update'e proxy olmalı
```

---

## Phase 2: Bütçe & Maliyet Takibi

### 2.1 — Budget Model
**Dosya:** `MasterConfig/Models/OrchestratorModels.swift` (yeni struct'lar ekle)

```swift
struct BudgetConfig: Codable {
    var monthlyLimitUSD: Double      // Aylık hard ceiling
    var softAlertThreshold: Double   // Uyarı eşiği (örn: %80)
    var currentSpendUSD: Double      // Mevcut harcama
    var tokenUsage: TokenUsage
    var autoPauseEnabled: Bool       // Limit aşılınca agent'ı durdur
}

struct TokenUsage: Codable {
    var inputTokens: Int
    var outputTokens: Int
    var totalCostUSD: Double
    var lastUpdated: Date
}

struct CostEntry: Codable, Identifiable {
    let id: String
    var agentName: String
    var projectId: String?
    var issueId: String?
    var inputTokens: Int
    var outputTokens: Int
    var costUSD: Double
    var model: String
    var timestamp: Date
}
```

### 2.2 — Cost Tracking Servisi
**Yeni dosya:** `MasterConfig/Services/BudgetService.swift`

- Agent başına maliyet tracking
- Günlük/haftalık/aylık raporlar
- Hard ceiling kontrolü — limit aşılınca agent'a SIGSTOP gönder
- Soft alert — eşik aşılınca UI'da uyarı göster
- Cost entry'leri `~/.claude/orchestrator/costs/` altında JSON olarak sakla

### 2.3 — Costs View
**Yeni dosya:** `MasterConfig/Views/Costs/CostsView.swift`

- **Dashboard:** Toplam harcama, agent bazlı breakdown
- **Grafikler:** Günlük harcama trendi (SwiftUI Charts)
- **Agent tablosu:** Her agent'ın limiti, harcaması, kalan bütçesi
- **Budget ayarlama:** Agent başına limit set etme
- **Alerts:** Son budget violation'lar

### 2.4 — MCP Server Cost Tool'ları
**Dosya:** `MasterConfig/MCP/orchestrator-mcp-server.js`

```javascript
// Yeni tool'lar:
- cost_log(agentName, inputTokens, outputTokens, costUSD, model)
- cost_report(agentName?, period?: "daily"|"weekly"|"monthly")
- budget_set(agentName, monthlyLimitUSD, softAlertThreshold?)
- budget_check(agentName) // kalan bütçeyi döner
```

---

## Phase 3: Governance & Approval Gates

### 3.1 — Approval Model
**Dosya:** `MasterConfig/Models/OrchestratorModels.swift`

```swift
struct ApprovalRequest: Codable, Identifiable {
    let id: String
    var type: ApprovalType         // agent_hire, budget_change, strategy_change, high_risk_action
    var title: String
    var description: String
    var requestedBy: String        // agent adı
    var status: ApprovalStatus     // pending, approved, rejected, revision_requested
    var decision: ApprovalDecision?
    var createdAt: Date
    var decidedAt: Date?
}

enum ApprovalType: String, Codable {
    case agentHire = "agent_hire"
    case budgetChange = "budget_change"
    case strategyChange = "strategy_change"
    case highRiskAction = "high_risk_action"
    case projectCreation = "project_creation"
}

struct ApprovalDecision: Codable {
    var decidedBy: String          // "board" (kullanıcı)
    var action: String             // approve, reject, revise
    var notes: String?
}
```

### 3.2 — Approval Gate Servisi
**Dosya:** `MasterConfig/Services/GovernanceService.swift` (yeni)

- Approval request oluşturma ve yönetme
- macOS notification ile kullanıcıya bildirim
- Agent'ı approval beklerken PAUSE durumuna alma
- Approval sonrası agent'a devam sinyali gönderme
- Approval geçmişi ve audit log
- Dosya: `~/.claude/orchestrator/approvals/`

### 3.3 — Approvals View
**Yeni dosya:** `MasterConfig/Views/Approvals/ApprovalsView.swift`

- **Pending queue:** Bekleyen onay talepleri (badge count sidebar'da)
- **Detay paneli:** Talep detayı, risk analizi, agent açıklaması
- **Aksiyon butonları:** Approve ✅ / Reject ❌ / Request Revision 🔄
- **Notlar:** Karar ile birlikte not ekleme
- **Geçmiş:** Tüm geçmiş kararlar

### 3.4 — MCP Server Approval Tool'ları
```javascript
- approval_request(type, title, description, requestedBy)
- approval_status(requestId) // agent'lar bunla kontrol eder
- approval_list(status?: "pending"|"approved"|"rejected")
```

---

## Phase 4: Org Chart & Agent Hiyerarşisi

### 4.1 — Org Model
**Dosya:** `MasterConfig/Models/OrchestratorModels.swift`

```swift
struct OrgNode: Codable, Identifiable {
    let id: String
    var agentName: String
    var role: OrgRole              // ceo, team_lead, engineer, specialist
    var title: String              // "Backend Lead", "Frontend Engineer"
    var reportsTo: String?         // parent agent ID
    var team: String?              // takım adı
    var responsibilities: [String]
    var skills: [String]
}

enum OrgRole: String, Codable, CaseIterable {
    case ceo = "CEO"
    case teamLead = "Team Lead"
    case engineer = "Engineer"
    case specialist = "Specialist"
}
```

### 4.2 — Org Chart View
**Yeni dosya:** `MasterConfig/Views/OrgChart/OrgChartView.swift`

- **Ağaç görünümü:** CEO → Team Leads → Engineers hiyerarşisi
- **Sürükle-bırak:** Agent'ları hiyerarşide taşıma
- **Agent kartları:** İsim, rol, status (active/idle/paused), mevcut task
- **Takım grupları:** Renkli gruplar halinde takımlar
- **Quick actions:** Sağ tık ile reassign, promote, remove

### 4.3 — Cross-team Delegation
OrchestratorService'e ekle:
- Bir team lead başka team'e task delegate edebilmeli
- Request depth tracking (kaç kez forward edildi)
- Delegation chain görüntüleme

---

## Phase 5: Routines (Recurring Tasks)

### 5.1 — Routine Model
```swift
struct Routine: Codable, Identifiable {
    let id: String
    var title: String
    var description: String
    var assignee: String
    var schedule: RoutineSchedule   // cron expression veya interval
    var issueTemplate: IssueTemplate // her çalışmada oluşturulacak issue
    var enabled: Bool
    var lastRun: Date?
    var nextRun: Date?
}

struct RoutineSchedule: Codable {
    var type: ScheduleType         // cron, interval, event
    var cronExpression: String?    // "0 9 * * 1-5" (hafta içi 09:00)
    var intervalMinutes: Int?
    var eventTrigger: String?      // "on_issue_close", "on_agent_idle"
}
```

### 5.2 — Routines View
**Yeni dosya:** `MasterConfig/Views/Routines/RoutinesView.swift`

- Routine listesi (enabled/disabled toggle)
- Yeni routine oluşturma (cron builder UI)
- Son çalışma logları
- Manuel tetikleme butonu

### 5.3 — Routine Executor
`OrchestratorService` içinde Timer-based routine checker:
- Her dakika aktif routine'ları kontrol et
- Zamanı geldiyse otomatik issue oluştur ve agent'a ata

---

## Phase 6: Activity Feed & Audit Trail

### 6.1 — Activity Model
```swift
struct ActivityEntry: Codable, Identifiable {
    let id: String
    var type: ActivityType     // issue_created, agent_spawned, approval_decided, cost_logged, etc.
    var actor: String          // agent veya "board"
    var summary: String        // "backend-agent completed issue #42"
    var metadata: [String: String]
    var timestamp: Date
}
```

### 6.2 — Activity Service
**Yeni dosya:** `MasterConfig/Services/ActivityService.swift`
- Tüm servislerdeki önemli olayları logla
- `~/.claude/orchestrator/activity.jsonl` (append-only)
- Filtreleme: agent, type, date range
- Real-time file watching ile UI güncellemesi

### 6.3 — Activity View Güncelleme
Mevcut OverviewView'daki activity bölümünü genişlet:
- Timeline görünümü (gruplandırılmış: bugün, dün, bu hafta)
- Agent bazlı filtreleme
- Activity type ikonları
- Detay popup'ları

---

## Phase 7: Config Import/Export

### 7.1 — Export
Tüm yapılandırmayı tek bir `.masterconfig` dosyasına paketle:
```json
{
  "version": "1.0",
  "exportDate": "2026-03-29",
  "config": {
    "teams": [...],
    "orgChart": [...],
    "agents": [...],
    "skills": [...],
    "mcpServers": [...],
    "routines": [...],
    "budgets": [...],
    "governanceRules": [...]
  }
}
```

### 7.2 — Import
- Dosya seçici ile `.masterconfig` dosyası seç
- Preview: nelerin import edileceğini göster
- Conflict resolution: mevcut config ile çakışmaları göster
- Selective import: sadece istenen bölümleri import et

### 7.3 — Settings View'a Ekle
SettingsView'a "Import/Export" sekmesi ekle.

---

## Implementasyon Sırası & Bağımlılıklar

```
Phase 1 (Hiyerarşik Tasks) ──────► ÖNCE BAŞLA — diğer her şeyin temeli
    │
    ├──► Phase 2 (Bütçe)          ► Phase 1'e bağlı (issue bazlı cost tracking)
    ├──► Phase 3 (Governance)      ► Phase 1'e bağlı (approval → issue lifecycle)
    │
    ├──► Phase 4 (Org Chart)       ► Phase 1 + 3'e bağlı (delegation + approval)
    ├──► Phase 5 (Routines)        ► Phase 1'e bağlı (issue template)
    │
    ├──► Phase 6 (Activity Feed)   ► Phase 1-5'e bağlı (tüm event'leri loglar)
    └──► Phase 7 (Import/Export)   ► En son — tüm modeller stabil olduktan sonra
```

---

## Dikkat Edilecekler

1. **Backward Compatibility:** Mevcut `tasks.json` ve MCP tool'ları çalışmaya devam etmeli
2. **File-based Architecture:** PostgreSQL yerine JSON dosyaları — performans için lazy loading
3. **Atomic Writes:** JSON dosyalarına yazarken temp file + rename pattern kullan (corruption önleme)
4. **SwiftUI Best Practices:** @Observable, MainActor, OutlineGroup, Charts framework
5. **Sidebar Badge'leri:** Pending approvals, unread activity için badge count
6. **Keyboard Shortcuts:** Her yeni view için Cmd+K palette'e entry ekle

---

## Dosya Değişiklik Özeti

| Değişiklik | Dosya |
|------------|-------|
| **Modifiye** | `AppModels.swift` — yeni model'ler |
| **Modifiye** | `OrchestratorModels.swift` — org, budget, approval model'leri |
| **Modifiye** | `TasksView.swift` — hiyerarşik yeniden tasarım |
| **Modifiye** | `OrchestratorService.swift` — hiyerarşi, budget, governance |
| **Modifiye** | `orchestrator-mcp-server.js` — yeni tool'lar |
| **Modifiye** | `ContentView.swift` — yeni nav section'lar |
| **Modifiye** | `SidebarView.swift` — yeni menü item'lar + badge'ler |
| **Modifiye** | `OverviewView.swift` — dashboard genişletme |
| **Modifiye** | `SettingsView.swift` — import/export sekmesi |
| **Modifiye** | `CommandPaletteView.swift` — yeni command'lar |
| **Yeni** | `BudgetService.swift` |
| **Yeni** | `GovernanceService.swift` |
| **Yeni** | `ActivityService.swift` |
| **Yeni** | `CostsView.swift` |
| **Yeni** | `ApprovalsView.swift` |
| **Yeni** | `OrgChartView.swift` |
| **Yeni** | `RoutinesView.swift` |
