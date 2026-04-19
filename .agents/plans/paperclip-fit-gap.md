# Paperclip Fit-Gap Analizi & İmplementasyon Planı
> Kaynak: https://github.com/paperclipai/paperclip
> Hedef: MasterConfig (native macOS SwiftUI)
> Oluşturulma: 2026-03-30 | Durum: Backlog

---

## Analiz Metodolojisi

Paperclip'in kaynak kodu (38.7K stars, 56 DB şeması, 71 servis dosyası) ile MasterConfig'in mevcut implementasyonu karşılaştırıldı. Gap'ler kritiklik sırasına göre önceliklendirildi.

---

## GAP #1 — Budget Enforcement (KRİTİK)

**Sorun:** `autoPauseEnabled` flag'i BudgetService'e yazılıyor ama hiçbir yerde kontrol edilmiyor. Cost overrun olduğunda agent otomatik durmuyor.

**Paperclip'te nasıl çalışıyor:**
- `budget_incidents` tablosu: threshold crossing'leri event olarak kaydeder
- Hard stop tetiklenince ilgili "work scope" pause edilir
- Otomatik approval request oluşturulur (budget override için)
- Approval gelince scope resume edilir

**MasterConfig'e yapılacaklar:**

- [ ] `BudgetService.logCost()` içinde her yazıştan sonra `checkAndEnforce()` çağır
- [ ] `checkAndEnforce()`: ratio > 1.0 ise `autoPauseEnabled` kontrolü yap
- [ ] OrchestratorService entegrasyonu: pause sinyali gönder (`.claude/orchestrator/agents/<name>/control` dosyasına `PAUSE` yaz)
- [ ] Agent'ların bu dosyayı polling ile okuması (MCP server veya agent CLAUDE.md hook'u)
- [ ] Soft threshold (ratio > softAlertThreshold): macOS notification gönder
- [ ] Hard threshold (ratio > 1.0): GovernanceService'e otomatik `budgetChange` approval request oluştur
- [ ] CostsView'da "Budget Incidents" bölümü ekle
- [ ] MCP `budget_check` tool'unu agent'lar her major işlem öncesi çağırmalı (CLAUDE.md'ye kural ekle)

**Dosyalar:** `BudgetService.swift`, `OrchestratorService.swift`, `CostsView.swift`, `orchestrator-mcp-server.js`

---

## GAP #2 — Routine Persistence (KRİTİK)

**Sorun:** RoutineService içindeki Timer sadece macOS uygulaması açıkken çalışıyor. Uygulama kapatılırsa routine'ler çalışmıyor.

**Paperclip'te nasıl çalışıyor:**
- Node.js server sürekli çalışır, routines DB-backed
- Cron expression + timezone support
- Catch-up policy: max 25 missed execution kuyruğa alınır
- Concurrency policy: `always_enqueue` / `skip_if_active` / `coalesce`

**MasterConfig'e yapılacaklar:**

- [ ] macOS `launchd` plist oluştur: `~/Library/LaunchAgents/com.masterconfig.routined.plist`
- [ ] Küçük bir Swift/Node.js daemon yaz: `~/.claude/orchestrator/routined` — sadece routine check yapar, MCP tool'larını çağırır
- [ ] Daemon, `routines.json`'u okur, `nextRun < now` ise issue oluşturur, `nextRun` günceller
- [ ] RoutineService'e `concurrencyPolicy` field'ı ekle (skipIfActive, alwaysEnqueue)
- [ ] RoutineSchedule'a `timezone` ve `catchUpPolicy` (maxMissed: Int) ekle
- [ ] Cron expression desteği: `swiftcron` veya basit parser ekle
- [ ] RoutinesView'a "Missed Executions" bölümü ekle

**Dosyalar:** `RoutineService.swift`, `AppModels.swift`, `RoutinesView.swift`, yeni `routined` daemon

---

## GAP #3 — Approval Auto-Pause Enforcement (KRİTİK)

**Sorun:** Approval request oluşturuluyor, kullanıcı onaylıyor/reddediyor ama agent bundan haberdar olmuyor. Real enforcement yok.

**Paperclip'te nasıl çalışıyor:**
- Approval pending → agent heartbeat'i PAUSE durumuna geçer
- Approval verilince → agent wakeup notification gönderilir, heartbeat resume eder

**MasterConfig'e yapılacaklar:**

- [ ] Agent control protokolü: `~/.claude/orchestrator/agents/<name>/status` dosyası
  - İçerik: `RUNNING` | `PAUSED` | `WAITING_APPROVAL:<requestId>`
- [ ] GovernanceService.createRequest() → agent status dosyasına `WAITING_APPROVAL:<id>` yaz
- [ ] GovernanceService.decide() → status dosyasını `RUNNING`'e döndür, macOS notification gönder
- [ ] MCP tool: `agent_status_check(agent_name)` — agent kendi durumunu polling ile okur
- [ ] ApprovalsView'da "Waiting Agents" widget ekle (hangi agent'lar bekliyor)
- [ ] Approval karar anında agent'a `message_send` ile bildirim gönder

**Dosyalar:** `GovernanceService.swift`, `ApprovalsView.swift`, `orchestrator-mcp-server.js`

---

## GAP #4 — Secrets Management (KRİTİK)

**Sorun:** API key'ler ve hassas veriler muhtemelen plain-text olarak CLAUDE.md veya environment dosyalarında duruyor. Versioning, redaction, strict mode yok.

**Paperclip'te nasıl çalışıyor:**
- Secrets DB'de versioned (SHA256 hash)
- Sensitive key detection regex: `/(api[-_]?key|access[-_]?token|auth|...)/i`
- Strict mode: sensitive key'ler için plain-text reddeder
- Redaction protection: `***REDACTED***` string'ini reddeder
- Secret reference: `secretId + version` ile env var'lara inject edilir

**MasterConfig'e yapılacaklar:**

- [ ] Yeni `SecretsService.swift` — macOS Keychain entegrasyonu
  - `setSecret(key, value)` → Keychain'e yaz
  - `getSecret(key)` → Keychain'den oku
  - `listSecretKeys()` → key listesini döndür (değerleri değil)
  - `deleteSecret(key)`
- [ ] Sensitive key detection: regex ile API key'leri tespit et
- [ ] SettingsView'a "Secrets" sekmesi ekle (key listesi, add/delete, değerler gizli)
- [ ] MCP tool: `secret_get(key)` → Keychain'den okur, agent'a döndürür
- [ ] MCP tool: `secret_set(key, value)` → Keychain'e yazar (board-level auth ile)
- [ ] Import/Export'ta secrets hariç tutulmalı, kullanıcıya uyarı gösterilmeli
- [ ] AppModels'e `SecretRef` tipi ekle: `{ key: String, version: Int }`

**Dosyalar:** Yeni `SecretsService.swift`, `SettingsView.swift`, `orchestrator-mcp-server.js`, `ImportExportService.swift`

---

## GAP #5 — Plugin System (YÜKSEK)

**Sorun:** Plugins view şu an boş bir placeholder. Paperclip'te 21 servislik bir plugin altyapısı var.

**Paperclip'te nasıl çalışıyor:**
- npm package veya local filesystem'den install
- 5-state lifecycle: `installed → ready → disabled → error → upgrade_pending`
- Her plugin ayrı worker process'te çalışır
- Plugin SDK ve `create-paperclip-plugin` scaffolding tool

**MasterConfig için minimum viable plugin sistemi:**

- [ ] Plugin manifest standardı belirle (`plugin.json`): name, version, description, entryPoint, tools[], permissions[]
- [ ] Plugin'ler `~/.claude/plugins/<name>/` altında yaşar
- [ ] `PluginService.swift`: load, enable, disable, install (local path'ten)
- [ ] MCP server'a plugin tool dispatch ekle: plugin'in tanımladığı tool'ları MCP'ye register et
- [ ] PluginsView'u implement et: plugin listesi, enable/disable toggle, install buton
- [ ] Plugin config UI: her plugin'in kendi config şeması
- [ ] Plugin health check: son çalışma zamanı, hata durumu
- [ ] İlk plugin örneği: `github-plugin` (repo fetch, PR oluşturma)

**Dosyalar:** Yeni `PluginService.swift`, `PluginsView.swift` (implement et), `orchestrator-mcp-server.js`

---

## GAP #6 — Execution Isolation (YÜKSEK)

**Sorun:** MasterConfig'de agent'lar aynı filesystem üzerinde çalışıyor. Paperclip her execution için git worktree oluşturuyor.

**Paperclip'te nasıl çalışıyor:**
- `workspace-runtime.ts`: git worktree per agent run
- Environment variable injection (branch, repo URL, workspace path)
- Service reuse with fingerprinting (aynı config → same worktree)
- Orphaned process detection ve cleanup

**MasterConfig'e yapılacaklar:**

- [ ] OrchestratorService'e `createWorktree(repoPath, branchName)` ekle
  - `git worktree add /tmp/mc-<uuid> <branch>` çalıştır
- [ ] Agent spawn'da worktree path'i environment variable olarak inject et
- [ ] Agent tamamlandığında `git worktree remove --force` cleanup
- [ ] OrgChartView'a agent'ın aktif worktree'sini göster
- [ ] `~/.claude/orchestrator/worktrees.json` ile aktif worktree'leri takip et

**Dosyalar:** `OrchestratorService.swift`, `OrgChartView.swift`

---

## GAP #7 — Issue Tracking Eksikleri (ORTA)

**Sorun:** Paperclip'te issue'lar daha zengin: inbox, markdown body, kanban, mention system, document attachments.

**MasterConfig'e yapılacaklar:**

- [ ] **Sub-issue UI**: TasksView'da parentIssueId varsa indent ederek göster
- [ ] **Kanban view**: TasksView'a toggle ekle (Liste / Kanban). Kanban: 5 sütun (Backlog→Done), issue kartları
- [ ] **Markdown rendering**: Issue description için `AttributedString` ile temel markdown render (bold, italic, code, liste)
- [ ] **File attachments UI**: Attachment ekleme butonu, dosya listesi, preview
- [ ] **Issue inbox**: "Bana atanan" ve "Benim oluşturduğum" filtreleri (MyIssues eşdeğeri)
- [ ] **Bulk actions**: Çoklu seçim + toplu status değiştirme

**Dosyalar:** `TasksView.swift`, `HierarchyService.swift`

---

## GAP #8 — Org Chart Eksikleri (ORTA)

**Sorun:** Org Chart çalışıyor ama bazı Paperclip özellikleri eksik.

**MasterConfig'e yapılacaklar:**

- [ ] **Drag & drop**: Agent kartlarını sürükleyerek hiyerarşide taşıma
- [ ] **PNG export**: Org chart'ı PNG olarak kaydet (SwiftUI `ImageRenderer`)
- [ ] **Adaptive collapse**: 10+ node'lu subtree'leri otomatik collapse et
- [ ] **Agent current task link**: Aktif agent'ın currentTask'ına tıklayınca ilgili issue'ya git

**Dosyalar:** `OrgChartView.swift`, `OrgService.swift`

---

## GAP #9 — Import/Export Tamamlama (ORTA)

**Sorun:** `ImportExportService.doImport()` implement edilmemiş.

**MasterConfig'e yapılacaklar:**

- [ ] `doImport()` tamamla: her section için merge logic yaz
- [ ] Conflict resolution uygula: skip / overwrite / rename
- [ ] Secrets import'ta hariç tut, kullanıcıya uyarı göster
- [ ] Import progress göstergesi ekle (her section için)
- [ ] Import sonrası tüm service'leri reload et

**Dosyalar:** `ImportExportService.swift`, `ImportExportView.swift`

---

## GAP #10 — Routine Cron & Timezone (ORTA)

**Sorun:** Routine schedule sadece basit interval/daily/weekly/monthly. Cron expression ve timezone yok.

**MasterConfig'e yapılacaklar:**

- [ ] `RoutineSchedule`'a `cronExpression: String?` ve `timezone: String?` ekle
- [ ] Basit cron parser implement et (5-field: min hour dom month dow)
- [ ] RoutinesView'da cron expression input field ekle (örnek: `0 9 * * 1-5`)
- [ ] Timezone picker ekle (TimeZone.knownTimeZoneIdentifiers listesi)

**Dosyalar:** `AppModels.swift`, `RoutineService.swift`, `RoutinesView.swift`

---

## Uygulama Sırası & Bağımlılıklar

```
GAP #4 (Secrets)          ← Bağımsız, güvenlik öncelikli, ÖNCE YAP
    │
GAP #1 (Budget Enforce)   ← BudgetService + OrchestratorService
GAP #3 (Approval Enforce) ← GovernanceService + OrchestratorService
    │
    ├──► GAP #2 (Routine Persist)   ← launchd daemon, bağımsız
    ├──► GAP #6 (Exec Isolation)    ← OrchestratorService
    │
GAP #5 (Plugin System)    ← Bağımsız, büyük efor
    │
GAP #7 (Issues UI)        ← Bağımsız, UI-only
GAP #8 (Org Chart)        ← Bağımsız, UI-only
GAP #9 (Import/Export)    ← Bağımsız, service tamamlama
GAP #10 (Cron/Timezone)   ← GAP #2 ile birlikte yap
```

---

## Efor Tahmini

| Gap | Efor | Öncelik |
|-----|------|---------|
| #1 Budget Enforcement | S (1-2 gün) | KRİTİK |
| #2 Routine Persistence | M (2-3 gün) | KRİTİK |
| #3 Approval Auto-pause | S (1 gün) | KRİTİK |
| #4 Secrets Management | M (2-3 gün) | KRİTİK |
| #5 Plugin System | XL (1-2 hafta) | YÜKSEK |
| #6 Execution Isolation | M (2-3 gün) | YÜKSEK |
| #7 Issue Tracking | M (2-3 gün) | ORTA |
| #8 Org Chart | S (1 gün) | ORTA |
| #9 Import/Export | S (1 gün) | ORTA |
| #10 Cron/Timezone | S (1 gün) | ORTA |

> S = Small (~1-2 gün), M = Medium (~2-3 gün), XL = Extra Large (1+ hafta)

---

## Kapsam Dışı (Mimari Farklılık)

Aşağıdaki Paperclip özellikleri MasterConfig'in single-user, local-first mimarisiyle uyumsuz — implement edilmeyecek:

| Özellik | Neden Kapsam Dışı |
|---------|-------------------|
| Multi-tenancy (çoklu şirket) | MasterConfig single-user, local macOS app |
| PostgreSQL | File-based JSON mimarisi kalacak |
| WebSocket real-time | FileWatcher polling yeterli |
| User authentication | Tek kullanıcı, auth gereksiz |
| AWS S3 storage | Local filesystem yeterli |
| CLI tool (ayrı binary) | MCP server karşılıyor |
| Docker deployment | Native macOS app |
| Playwright E2E tests | XCTest kullanılacak |
