# Plan: Mio-Inspired Memory Layer Integration

> Mio.fyi'dan ilham alan 5 katmanlı bellek sistemi — Claude Code projelerine entegrasyon
> Oluşturulma: 2026-03-26

## Feature Description

Claude Code oturumları arasında bilgi kaybını önlemek için Mio.fyi'dan ilham alan yapılandırılmış, otomatik ve semantik-aranabilir bir bellek katmanı. Mevcut dosya tabanlı MEMORY.md sistemini 5 katmanlı bir mimariye yükselterek: otomatik kısa süreli bellek, güven skorlu tercih çıkarımı, Supabase destekli uzun süreli episodik bellek, prosedürel skill data ve cross-session konsolidasyon sağlar.

## Success Criteria

- [ ] Her konuşma sonunda 5 alanlı yapılandırılmış recent memory otomatik kaydediliyor
- [ ] Kullanıcı tercihleri konuşmalardan otomatik çıkarılıp güven skoru ile kaydediliyor
- [ ] Episodik anılar Supabase'de saklanıp semantik arama ile sorgulanabiliyor
- [ ] Skill data tabloları Supabase'de oluşturulup MCP üzerinden erişilebiliyor
- [ ] Günlük cron ile cross-session konsolidasyon çalışıyor
- [ ] Mevcut MEMORY.md sistemi ile geriye uyumlu çalışıyor
- [ ] Tüm katmanlar MCP tool olarak erişilebiliyor

## Mimari Genel Bakış

```
┌─────────────────────────────────────────────────────────────┐
│                    Claude Code Session                       │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  Hook: conversation-end         Hook: session-start         │
│  ┌──────────────────┐          ┌──────────────────┐        │
│  │ Recent Memory    │          │ Memory Loader    │        │
│  │ Writer           │          │ (inject context) │        │
│  └────────┬─────────┘          └────────┬─────────┘        │
│           │                             │                   │
├───────────┼─────────────────────────────┼───────────────────┤
│           ▼                             ▼                   │
│  ┌─────────────────────────────────────────────────────┐   │
│  │              Memory MCP Server                       │   │
│  │                                                     │   │
│  │  Tools:                                             │   │
│  │  • memory_save_recent    (Katman 2)                 │   │
│  │  • memory_get_recent     (Katman 2)                 │   │
│  │  • preference_extract    (Katman 3)                 │   │
│  │  • preference_get        (Katman 3)                 │   │
│  │  • memory_store          (Katman 4)                 │   │
│  │  • memory_search         (Katman 4)                 │   │
│  │  • memory_consolidate    (Katman 5)                 │   │
│  └─────────┬───────────────────────────┬───────────────┘   │
│            │                           │                    │
│    ┌───────▼───────┐          ┌────────▼────────┐          │
│    │  Dosya Sistemi │          │    Supabase     │          │
│    │  (Katman 2-3) │          │   (Katman 4-5)  │          │
│    │               │          │                 │          │
│    │ recent.json   │          │ memories        │          │
│    │ preferences/  │          │ preferences     │          │
│    │ sessions/     │          │ skill_data      │          │
│    └───────────────┘          │ consolidation   │          │
│                               └─────────────────┘          │
└─────────────────────────────────────────────────────────────┘

        ┌──────────────────────────────────┐
        │    Cron: Sleep-Time Reflection   │
        │    (24h cycle — Katman 5)        │
        │                                  │
        │  1. Son 24h session'ları oku     │
        │  2. Pattern'ları çıkar           │
        │  3. Episodik belleğe kaydet      │
        │  4. Tercihleri konsolide et      │
        │  5. Stale memory'leri temizle    │
        └──────────────────────────────────┘
```

## Relevant Files

| File | Purpose | Action |
|------|---------|--------|
| `~/.claude/mcp-servers/memory-mcp-server.js` | Memory MCP sunucusu | **Create** |
| `~/.claude/hooks/memory-save-recent.sh` | Konuşma sonu recent memory kaydetme | **Create** |
| `~/.claude/hooks/memory-load-context.sh` | Oturum başında bellek yükleme | **Create** |
| `~/.claude/memory/recent.json` | Yapılandırılmış kısa süreli bellek | **Create** |
| `~/.claude/memory/preferences.json` | Otomatik çıkarılan tercihler | **Create** |
| `~/.claude/memory/sessions/` | Oturum özetleri dizini | **Create** |
| `~/.claude/scripts/sleep-time-reflection.sh` | Günlük konsolidasyon cron scripti | **Create** |
| `~/.claude/settings.json` | MCP server + hook kayıtları | **Modify** |
| `~/.claude/CLAUDE.md` | Memory katmanı kullanım talimatları | **Modify** |
| Supabase: `memories` table | Episodik bellek tablosu | **Create (SQL)** |
| Supabase: `user_preferences` table | Tercihler tablosu | **Create (SQL)** |
| Supabase: `session_summaries` table | Oturum özetleri | **Create (SQL)** |
| Supabase: `consolidation_log` table | Konsolidasyon geçmişi | **Create (SQL)** |

## Architecture Notes

### Neden Ayrı MCP Server?
Orchestrator MCP server zaten 436 satır ve kendi sorumluluğu var (task board + messaging). Memory katmanını ayrı bir MCP server olarak tutmak:
- Tek sorumluluk ilkesine uygun
- Bağımsız geliştirme ve test
- Orchestrator olmadan da çalışabilir (tüm projeler için)

### Hibrit Depolama Stratejisi
- **Dosya sistemi** (Katman 2-3): Hızlı erişim, her oturumda yüklenir, offline çalışır
- **Supabase** (Katman 4-5): Cross-device, semantik arama, büyük veri, konsolidasyon

### Mio'dan Farklılaşma
- Mio kendi API'si ile Haiku/Sonnet çağırıyor — biz Claude Code hooks + MCP kullanıyoruz
- Mio LanceDB kullanıyor — biz Supabase pg_vector veya trigram search kullanacağız
- Mio'da working memory yönetimi var — bizde Claude Code bunu zaten yönetiyor

---

## Implementation Phases

### Phase 1 — Temel Altyapı: Memory MCP Server + Dosya Yapısı
**Goal**: Memory MCP server'ı oluştur, dosya yapısını kur, settings.json'a kaydet

#### Task 1.1 — Dizin yapısını oluştur
**Action**: Create directories

```bash
mkdir -p ~/.claude/memory/sessions
mkdir -p ~/.claude/scripts
```

**Başlangıç dosyaları:**

```json
// ~/.claude/memory/recent.json
{
  "version": 1,
  "updated_at": null,
  "project": null,
  "purpose_and_context": "",
  "current_state": "",
  "key_learnings": "",
  "approach_and_patterns": "",
  "tools_and_resources": ""
}
```

```json
// ~/.claude/memory/preferences.json
{
  "version": 1,
  "preferences": {},
  "candidates": []
}
```

**Validation**: `ls ~/.claude/memory/ && cat ~/.claude/memory/recent.json`

---

#### Task 1.2 — Memory MCP Server oluştur
**File**: `~/.claude/mcp-servers/memory-mcp-server.js`
**Action**: Create

Node.js MCP server — `@modelcontextprotocol/sdk` kullanarak (orchestrator ile aynı dependency).

**Araçlar (tools):**

```javascript
// ===== KATMAN 2: Recent Memory =====

// memory_save_recent — Konuşma sonunda yapılandırılmış özet kaydet
{
  name: "memory_save_recent",
  description: "Save structured recent memory for the current/last session",
  inputSchema: {
    type: "object",
    properties: {
      project: { type: "string", description: "Project/repo name" },
      purpose_and_context: { type: "string" },
      current_state: { type: "string" },
      key_learnings: { type: "string" },
      approach_and_patterns: { type: "string" },
      tools_and_resources: { type: "string" }
    },
    required: ["project", "purpose_and_context"]
  }
}
// → ~/.claude/memory/recent.json yazılır
// → ~/.claude/memory/sessions/{date}_{project}.json olarak da arşivlenir

// memory_get_recent — Son recent memory'yi oku
{
  name: "memory_get_recent",
  description: "Get the most recent structured memory",
  inputSchema: {
    type: "object",
    properties: {
      project: { type: "string", description: "Filter by project name" }
    }
  }
}

// memory_list_sessions — Geçmiş oturum özetlerini listele
{
  name: "memory_list_sessions",
  description: "List past session summaries",
  inputSchema: {
    type: "object",
    properties: {
      project: { type: "string" },
      limit: { type: "number", default: 10 },
      since: { type: "string", description: "ISO date string" }
    }
  }
}

// ===== KATMAN 3: User Preferences =====

// preference_extract — Konuşmadan tercih adayı çıkar
{
  name: "preference_extract",
  description: "Extract a preference candidate from conversation",
  inputSchema: {
    type: "object",
    properties: {
      key: { type: "string", description: "Canonical key, e.g. 'code_style.commit_message'" },
      value: { type: "string" },
      confidence: { type: "number", minimum: 0, maximum: 1 },
      source: { type: "string", description: "What triggered this extraction" }
    },
    required: ["key", "value", "confidence"]
  }
}
// → confidence >= 0.75 ise preferences.json'a yaz
// → confidence < 0.75 ise candidates listesine ekle

// preference_get — Tercihleri oku
{
  name: "preference_get",
  description: "Get user preferences, optionally filtered by key prefix",
  inputSchema: {
    type: "object",
    properties: {
      prefix: { type: "string", description: "Key prefix filter, e.g. 'code_style'" }
    }
  }
}

// ===== KATMAN 4: Episodic Memory (Supabase) =====

// memory_store — Uzun süreli anı kaydet
{
  name: "memory_store",
  description: "Store a long-term episodic memory in Supabase",
  inputSchema: {
    type: "object",
    properties: {
      category: {
        type: "string",
        enum: ["technical", "personal", "project", "pattern", "decision"]
      },
      content: { type: "string" },
      project: { type: "string" },
      confidence: { type: "number", minimum: 0, maximum: 1 },
      tags: { type: "array", items: { type: "string" } }
    },
    required: ["category", "content", "confidence"]
  }
}

// memory_search — Semantik arama ile anıları bul
{
  name: "memory_search",
  description: "Search episodic memories by text similarity or tags",
  inputSchema: {
    type: "object",
    properties: {
      query: { type: "string" },
      category: { type: "string" },
      project: { type: "string" },
      limit: { type: "number", default: 5 },
      min_confidence: { type: "number", default: 0.5 }
    },
    required: ["query"]
  }
}

// ===== KATMAN 5: Consolidation =====

// memory_consolidate — Manuel konsolidasyon tetikle
{
  name: "memory_consolidate",
  description: "Trigger memory consolidation: merge recent sessions, extract patterns",
  inputSchema: {
    type: "object",
    properties: {
      since: { type: "string", description: "ISO date — consolidate sessions since this date" },
      dry_run: { type: "boolean", default: false }
    }
  }
}
```

**Depolama mantığı:**

```
memory_save_recent:
  1. ~/.claude/memory/recent.json güncelle (overwrite — en güncel)
  2. ~/.claude/memory/sessions/2026-03-26_MasterConfig.json olarak arşivle
  3. Supabase bağlıysa → session_summaries tablosuna da INSERT

memory_store:
  1. Supabase bağlıysa → memories tablosuna INSERT
  2. Supabase yoksa → ~/.claude/memory/episodes/{id}.json olarak dosyaya kaydet (fallback)

memory_search:
  1. Supabase bağlıysa → trigram search (pg_trgm) veya full-text search
  2. Supabase yoksa → lokal dosyalarda basit string match

memory_consolidate:
  1. ~/.claude/memory/sessions/ altındaki dosyaları oku
  2. Tekrarlayan pattern'ları bul
  3. Güven skoru düşük preference candidate'leri yükselt (birden fazla session'da geçiyorsa)
  4. Yeni episodik anılar oluştur
  5. consolidation_log tablosuna kaydet
```

**Validation**: `node ~/.claude/mcp-servers/memory-mcp-server.js --test`

---

#### Task 1.3 — Settings.json'a MCP server kaydı
**File**: `~/.claude/settings.json`
**Action**: Modify

```json
{
  "mcpServers": {
    "memory": {
      "type": "stdio",
      "command": "/opt/homebrew/bin/node",
      "args": ["/Users/onur/.claude/mcp-servers/memory-mcp-server.js"]
    }
    // ... existing servers
  }
}
```

**Validation**: Yeni Claude Code session başlat, `mcp__memory__*` tool'ları görünmeli

---

### Phase 2 — Katman 2: Recent Memory + Hooks
**Goal**: Her konuşma sonunda otomatik yapılandırılmış bellek kaydetme

#### Task 2.1 — Session-end hook oluştur
**File**: `~/.claude/hooks/memory-save-recent.sh`
**Action**: Create

```bash
#!/bin/bash
# Hook: Konuşma sonu — Claude'a recent memory kaydetmesini hatırlat
# Trigger: Stop (conversation end)

# Claude'a bir system reminder enjekte et
echo "IMPORTANT: Before ending, save a structured recent memory using memory_save_recent tool with: purpose_and_context, current_state, key_learnings, approach_and_patterns, tools_and_resources"
```

> **Not:** Claude Code hook'ları doğrudan MCP tool çağıramaz. Hook'un yapabileceği şey Claude'a hatırlatma göndermek veya dosya sistemi üzerinde işlem yapmaktır. Alternatif yaklaşım: CLAUDE.md'ye "her konuşma sonunda memory_save_recent çağır" talimatı eklemek daha güvenilir olabilir.

**Alternatif yaklaşım — CLAUDE.md talimatı:**
```markdown
## Memory Protocol
Her konuşma sonunda (kullanıcı "bye", "teşekkürler", "tamam bu kadar" dediğinde veya
uzun bir task tamamlandığında) `memory_save_recent` tool'unu çağır:
- project: çalıştığın proje adı
- purpose_and_context: bu oturumda ne yaptık ve neden
- current_state: iş nerede kaldı
- key_learnings: öğrenilen önemli şeyler
- approach_and_patterns: işe yarayan yaklaşımlar
- tools_and_resources: kullanılan araçlar ve kaynaklar
```

#### Task 2.2 — Session-start hook: context injection
**File**: `~/.claude/hooks/memory-load-context.sh`
**Action**: Create

```bash
#!/bin/bash
# Hook: Oturum başlangıcı — son recent memory'yi yükle
# Trigger: SessionStart

RECENT="$HOME/.claude/memory/recent.json"
if [ -f "$RECENT" ] && [ -s "$RECENT" ]; then
  PROJECT=$(jq -r '.project // "unknown"' "$RECENT" 2>/dev/null)
  UPDATED=$(jq -r '.updated_at // "never"' "$RECENT" 2>/dev/null)
  PURPOSE=$(jq -r '.purpose_and_context // ""' "$RECENT" 2>/dev/null)
  STATE=$(jq -r '.current_state // ""' "$RECENT" 2>/dev/null)

  if [ -n "$PURPOSE" ] && [ "$PURPOSE" != "" ]; then
    echo "Last session ($PROJECT, $UPDATED): $PURPOSE | State: $STATE"
  fi
fi
```

**Validation**: Yeni session başlat, StatusLine'da veya hook çıktısında son oturum bilgisi görünmeli

#### Task 2.3 — Settings.json'a hook kayıtları
**File**: `~/.claude/settings.json`
**Action**: Modify

```json
{
  "hooks": {
    "SessionStart": [
      // ... existing hooks
      {
        "command": "bash ~/.claude/hooks/memory-load-context.sh",
        "timeout": 5000
      }
    ],
    "Stop": [
      {
        "command": "bash ~/.claude/hooks/memory-save-recent.sh",
        "timeout": 3000
      }
    ]
  }
}
```

**Validation**: `cat ~/.claude/settings.json | jq '.hooks'`

---

### Phase 3 — Katman 3: User Preferences — Otomatik Çıkarım
**Goal**: Konuşmalardan kullanıcı tercihlerini otomatik çıkar ve güven skoru ile kaydet

#### Task 3.1 — Preference sistemi (MCP server içinde)
**Zaten Task 1.2'de tanımlanan** `preference_extract` ve `preference_get` tool'ları.

**Kanonik anahtar seti (allowlist):**

```javascript
const CANONICAL_KEYS = {
  // Kod stili
  "code_style.language": "Preferred programming language",
  "code_style.commit_message": "Commit message format preference",
  "code_style.naming": "Variable/function naming convention",
  "code_style.comments": "Comment style preference",

  // İletişim
  "communication.language": "Response language preference",
  "communication.verbosity": "How verbose responses should be",
  "communication.tone": "Formal/informal preference",
  "communication.emoji": "Emoji usage preference",

  // İş akışı
  "workflow.testing": "Testing approach preference",
  "workflow.git": "Git workflow preference",
  "workflow.review": "Code review style",
  "workflow.planning": "Planning depth preference",

  // Araçlar
  "tools.editor": "Preferred editor/IDE",
  "tools.terminal": "Terminal preference",
  "tools.browser": "Browser preference",

  // Kişisel
  "personal.name": "User's name",
  "personal.role": "User's role",
  "personal.timezone": "User's timezone",
  "personal.expertise": "Areas of expertise"
};
```

**Güven mantığı:**
```
confidence >= 0.75 + kanonik anahtar eşleşmesi → Hemen kaydet
confidence >= 0.50 + kanonik anahtar → Candidate olarak kaydet
confidence < 0.50 → Atla

Candidate → Preference yükseltme:
  Aynı candidate 3+ session'da tekrar ederse → otomatik yükselt
  Kullanıcı onayı ile → hemen yükselt
```

#### Task 3.2 — CLAUDE.md'ye preference extraction talimatı
**File**: `~/.claude/CLAUDE.md`
**Action**: Modify — Learned Patterns bölümüne ekle

```markdown
### Pattern: Auto Preference Extraction (v1.0)
**Context**: Kullanıcı bir tercih belirttiğinde
**Learning**: Konuşma sırasında kullanıcı tercihleri ifade ettiğinde
  (örn. "snake_case kullan", "Türkçe yaz", "test yazmadan geçme") otomatik olarak
  `preference_extract` tool'unu çağır.
**Action**: Tercihi kanonik anahtar ile eşleştir, güven skoru ver, kaydet.
  Açık talimatlar (0.9+), dolaylı göstergeler (0.6-0.8), tahminler (0.3-0.5).
```

**Validation**: Bir sonraki konuşmada "ben hep snake_case kullanırım" deyince preference kaydedilmeli

---

### Phase 4 — Katman 4: Episodic Memory — Supabase Entegrasyonu
**Goal**: Uzun süreli anıları Supabase'de saklayıp semantik arama ile sorgulanabilir yap

#### Task 4.1 — Supabase projesi oluştur/bağla
**Action**: Supabase dashboard'dan yeni proje veya mevcut projeye tablo ekle

```bash
# .env.supabase dosyası oluştur
cat > ~/.claude/.env.supabase << 'EOF'
SUPABASE_URL=https://xxxxx.supabase.co
SUPABASE_SERVICE_ROLE_KEY=eyJhbGci...
EOF
```

**Validation**: `mcp__supabase__connect` ile bağlantı test et

#### Task 4.2 — Veritabanı şeması oluştur
**Action**: Supabase SQL editor veya MCP üzerinden

```sql
-- Katman 4: Episodik Bellek
CREATE TABLE memories (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  category VARCHAR(50) NOT NULL CHECK (category IN (
    'technical', 'personal', 'project', 'pattern', 'decision'
  )),
  content TEXT NOT NULL,
  project VARCHAR(200),
  confidence NUMERIC(3,2) DEFAULT 0.80,
  tags TEXT[] DEFAULT '{}',
  source_session VARCHAR(100),
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  is_consolidated BOOLEAN DEFAULT FALSE,
  expires_at TIMESTAMPTZ  -- NULL = kalıcı
);

-- Full-text search index
ALTER TABLE memories ADD COLUMN fts tsvector
  GENERATED ALWAYS AS (to_tsvector('english', content)) STORED;
CREATE INDEX idx_memories_fts ON memories USING GIN (fts);

-- Trigram search (fuzzy matching)
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_memories_trgm ON memories USING GIN (content gin_trgm_ops);

-- Filtreleme indexleri
CREATE INDEX idx_memories_category ON memories (category);
CREATE INDEX idx_memories_project ON memories (project);
CREATE INDEX idx_memories_confidence ON memories (confidence);
CREATE INDEX idx_memories_created ON memories (created_at DESC);

-- Katman 3: User Preferences (Supabase mirror)
CREATE TABLE user_preferences (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  key VARCHAR(200) NOT NULL UNIQUE,
  value TEXT NOT NULL,
  confidence NUMERIC(3,2) NOT NULL,
  source TEXT,
  times_confirmed INTEGER DEFAULT 1,
  created_at TIMESTAMPTZ DEFAULT NOW(),
  updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Session özetleri
CREATE TABLE session_summaries (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  project VARCHAR(200),
  purpose_and_context TEXT,
  current_state TEXT,
  key_learnings TEXT,
  approach_and_patterns TEXT,
  tools_and_resources TEXT,
  session_date DATE DEFAULT CURRENT_DATE,
  created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_sessions_project ON session_summaries (project);
CREATE INDEX idx_sessions_date ON session_summaries (session_date DESC);

-- Konsolidasyon logu
CREATE TABLE consolidation_log (
  id UUID DEFAULT gen_random_uuid() PRIMARY KEY,
  sessions_processed INTEGER,
  memories_created INTEGER,
  preferences_updated INTEGER,
  patterns_found JSONB,
  ran_at TIMESTAMPTZ DEFAULT NOW()
);

-- Arama fonksiyonu (similarity threshold)
CREATE OR REPLACE FUNCTION search_memories(
  search_query TEXT,
  category_filter VARCHAR DEFAULT NULL,
  project_filter VARCHAR DEFAULT NULL,
  min_confidence NUMERIC DEFAULT 0.5,
  result_limit INTEGER DEFAULT 5
)
RETURNS TABLE (
  id UUID,
  category VARCHAR,
  content TEXT,
  project VARCHAR,
  confidence NUMERIC,
  tags TEXT[],
  similarity REAL,
  created_at TIMESTAMPTZ
) AS $$
BEGIN
  RETURN QUERY
  SELECT
    m.id, m.category, m.content, m.project,
    m.confidence, m.tags,
    similarity(m.content, search_query) AS similarity,
    m.created_at
  FROM memories m
  WHERE
    m.confidence >= min_confidence
    AND (category_filter IS NULL OR m.category = category_filter)
    AND (project_filter IS NULL OR m.project = project_filter)
    AND (m.expires_at IS NULL OR m.expires_at > NOW())
    AND (
      m.fts @@ plainto_tsquery('english', search_query)
      OR similarity(m.content, search_query) > 0.1
    )
  ORDER BY
    similarity(m.content, search_query) DESC,
    m.confidence DESC
  LIMIT result_limit;
END;
$$ LANGUAGE plpgsql;
```

**Validation**: `mcp__supabase__list_tables` ile tabloların oluştuğunu doğrula

#### Task 4.3 — MCP Server'a Supabase entegrasyonu
**File**: `~/.claude/mcp-servers/memory-mcp-server.js`
**Action**: Modify — `memory_store` ve `memory_search` tool'larına Supabase çağrıları ekle

```javascript
// Supabase bağlantısı — .env.supabase'den oku
const SUPABASE_ENV = path.join(os.homedir(), '.claude', '.env.supabase');

function loadSupabaseConfig() {
  if (!fs.existsSync(SUPABASE_ENV)) return null;
  const env = fs.readFileSync(SUPABASE_ENV, 'utf8');
  const url = env.match(/SUPABASE_URL=(.+)/)?.[1]?.trim();
  const key = env.match(/SUPABASE_SERVICE_ROLE_KEY=(.+)/)?.[1]?.trim();
  if (!url || !key) return null;
  return { url, key };
}

// REST API ile Supabase çağrısı (dependency-free)
async function supabaseQuery(method, table, params = {}) {
  const config = loadSupabaseConfig();
  if (!config) throw new Error('Supabase not configured');

  const url = new URL(`/rest/v1/${table}`, config.url);
  // ... fetch with Authorization: Bearer key
}

// RPC çağrısı (search_memories fonksiyonu için)
async function supabaseRPC(fn, params) {
  const config = loadSupabaseConfig();
  if (!config) throw new Error('Supabase not configured');

  const response = await fetch(`${config.url}/rest/v1/rpc/${fn}`, {
    method: 'POST',
    headers: {
      'apikey': config.key,
      'Authorization': `Bearer ${config.key}`,
      'Content-Type': 'application/json'
    },
    body: JSON.stringify(params)
  });
  return response.json();
}
```

**Validation**: `memory_store` ile bir anı kaydet, `memory_search` ile geri bul

---

### Phase 5 — Katman 5: Sleep-Time Reflection (Konsolidasyon)
**Goal**: Günlük cron ile tüm oturum özetlerini analiz et, pattern çıkar, belleği konsolide et

#### Task 5.1 — Konsolidasyon scripti
**File**: `~/.claude/scripts/sleep-time-reflection.sh`
**Action**: Create

```bash
#!/bin/bash
# Sleep-Time Reflection — Günlük bellek konsolidasyonu
# Cron: 0 3 * * * (her gün saat 03:00)

MEMORY_DIR="$HOME/.claude/memory"
SESSIONS_DIR="$MEMORY_DIR/sessions"
LOG_FILE="$MEMORY_DIR/consolidation.log"

echo "$(date -Iseconds) — Starting sleep-time reflection" >> "$LOG_FILE"

# Son 24 saatteki session dosyalarını bul
RECENT_SESSIONS=$(find "$SESSIONS_DIR" -name "*.json" -mtime -1 2>/dev/null)

if [ -z "$RECENT_SESSIONS" ]; then
  echo "$(date -Iseconds) — No recent sessions to consolidate" >> "$LOG_FILE"
  exit 0
fi

# Claude Code'u headless modda çağırarak konsolidasyon yap
# (claude --print ile non-interactive mode)
claude --print \
  --model haiku \
  "Sen bir bellek konsolidasyon ajanısın. Aşağıdaki oturum özetlerini analiz et:

$(for f in $RECENT_SESSIONS; do
  echo "=== $(basename $f) ==="
  cat "$f"
  echo ""
done)

Görevlerin:
1. Tekrarlayan pattern'ları belirle
2. Önemli öğrenmeleri episodik belleğe kaydet (memory_store tool)
3. Tercih adaylarını güncelle (preference_extract tool)
4. Kısa bir konsolidasyon raporu yaz

memory_consolidate tool'unu çağır." 2>> "$LOG_FILE"

echo "$(date -Iseconds) — Reflection complete" >> "$LOG_FILE"
```

> **Not:** `claude --print` headless modda çalışabilir. Eğer MCP tool erişimi olmuyorsa, script doğrudan Supabase REST API çağırabilir.

#### Task 5.2 — Alternatif: Node.js konsolidasyon scripti
**File**: `~/.claude/scripts/consolidate.js`
**Action**: Create

Daha güvenilir alternatif — doğrudan Supabase REST API kullanarak:

```javascript
// 1. Son 24h session dosyalarını oku
// 2. Pattern extraction (basit keyword frequency + co-occurrence)
// 3. Yeni memories INSERT
// 4. Preference candidates'ı güncelle (tekrar sayısına göre confidence artır)
// 5. consolidation_log'a kaydet
```

#### Task 5.3 — Cron job kurulumu
**Action**: System cron

```bash
# Günlük 03:00'da çalışır
crontab -e
0 3 * * * /bin/bash ~/.claude/scripts/sleep-time-reflection.sh
```

Veya Claude Code'un kendi `/schedule` özelliği ile:
```
/schedule "Memory consolidation" --cron "0 3 * * *" --command "node ~/.claude/scripts/consolidate.js"
```

**Validation**: `bash ~/.claude/scripts/sleep-time-reflection.sh` manuel çalıştırıp log kontrol et

---

### Phase 6 — Entegrasyon: CLAUDE.md + Skill Dosyası
**Goal**: Tüm katmanları Claude Code'un doğal iş akışına entegre et

#### Task 6.1 — CLAUDE.md'ye Memory Protocol ekle
**File**: `~/.claude/CLAUDE.md`
**Action**: Modify

```markdown
## Memory Layer Protocol (Mio-Inspired)

### Katman 2 — Recent Memory
Her konuşma sonunda `memory_save_recent` çağır. Alanlar:
- purpose_and_context: Bu oturumda ne yaptık
- current_state: İş nerede kaldı
- key_learnings: Öğrenilen şeyler
- approach_and_patterns: İşe yarayan yaklaşımlar
- tools_and_resources: Kullanılan araçlar

### Katman 3 — Preference Extraction
Kullanıcı bir tercih belirttiğinde `preference_extract` çağır.
Güven skoru: doğrudan talimat (0.9+), dolaylı (0.6-0.8), tahmin (0.3-0.5).
Sadece kanonik anahtarlarla eşleşen tercihler kabul edilir.

### Katman 4 — Episodic Memory
Önemli kararlar, keşifler veya pattern'lar için `memory_store` çağır.
Yeni bir konuya başlarken `memory_search` ile ilgili anıları kontrol et.

### Katman 5 — Konsolidasyon
Manuel: `memory_consolidate` çağır.
Otomatik: Günlük 03:00'da cron çalışır.
```

#### Task 6.2 — Memory skill dosyası oluştur
**File**: `~/.claude/skills/memory-layer/SKILL.md`
**Action**: Create

```markdown
---
name: memory-layer
description: Mio-inspired 5-layer memory system for Claude Code
trigger: When working with memory, preferences, or cross-session context
---

# Memory Layer Skill

## Available Tools
- `memory_save_recent` — Yapılandırılmış oturum özeti kaydet
- `memory_get_recent` — Son oturum özetini oku
- `memory_list_sessions` — Geçmiş oturumları listele
- `preference_extract` — Tercih adayı çıkar
- `preference_get` — Kayıtlı tercihleri oku
- `memory_store` — Uzun süreli anı kaydet (Supabase)
- `memory_search` — Anılarda semantik arama (Supabase)
- `memory_consolidate` — Bellek konsolidasyonu tetikle

## Usage Patterns
[Skill kullanım örnekleri ve senaryolar]
```

**Validation**: `/prime` çalıştırıp memory tool'larının görünüp görünmediğini kontrol et

---

## Testing Strategy

- [ ] **Unit**: MCP server'ın her tool'unu doğrudan test et (`--test` flag'i)
- [ ] **Integration**: Session-start hook → recent memory yükleme → gösterim
- [ ] **Integration**: Konuşma → preference_extract → preferences.json güncelleme
- [ ] **Integration**: memory_store → Supabase INSERT → memory_search ile geri bulma
- [ ] **E2E**: Tam oturum: başla → çalış → recent memory kaydet → yeni session → yükle
- [ ] **E2E**: 3 session sonra → consolidate → pattern çıkarıldığını doğrula
- [ ] **Manuel**: Supabase dashboard'dan tabloları kontrol et

## Validation Commands

```bash
# MCP server çalışıyor mu?
echo '{"jsonrpc":"2.0","method":"tools/list","id":1}' | node ~/.claude/mcp-servers/memory-mcp-server.js

# Dosya yapısı doğru mu?
ls -la ~/.claude/memory/
cat ~/.claude/memory/recent.json
cat ~/.claude/memory/preferences.json

# Supabase tabloları var mı?
# (MCP üzerinden: mcp__supabase__list_tables)

# Hook'lar kayıtlı mı?
cat ~/.claude/settings.json | jq '.hooks'

# Cron kurulu mu?
crontab -l | grep sleep-time
```

## Dependency Order

```
Phase 1 (Temel)
  ├── Task 1.1 (dizinler) ──────► Task 1.2 (MCP server)
  │                                   │
  │                                   ▼
  │                              Task 1.3 (settings.json)
  │                                   │
  ▼                                   ▼
Phase 2 (Recent Memory)         Phase 3 (Preferences)
  ├── Task 2.1 (hook)             ├── Task 3.1 (MCP'de zaten var)
  ├── Task 2.2 (load hook)        └── Task 3.2 (CLAUDE.md)
  └── Task 2.3 (settings)
        │                              │
        ▼                              ▼
      Phase 4 (Supabase) ◄────────────┘
        ├── Task 4.1 (proje bağla)
        ├── Task 4.2 (şema)
        └── Task 4.3 (MCP Supabase)
              │
              ▼
        Phase 5 (Consolidation)
        ├── Task 5.1 veya 5.2 (script)
        └── Task 5.3 (cron)
              │
              ▼
        Phase 6 (Entegrasyon)
        ├── Task 6.1 (CLAUDE.md)
        └── Task 6.2 (skill)
```

## Risk Analizi

| Risk | Etki | Mitigasyon |
|------|------|------------|
| Claude Code hook'ları MCP tool çağıramaz | Yüksek | CLAUDE.md talimatı + Stop hook'ta hatırlatma |
| Supabase bağlantısı olmadan çalışmazsa | Orta | Dosya sistemi fallback her zaman aktif |
| `claude --print` headless modda MCP erişimi yok | Orta | Node.js script ile doğrudan REST API |
| Konsolidasyon kalitesi düşük olabilir | Düşük | Basit pattern matching + keyword frequency yeterli başlangıç |
| Token maliyeti artışı | Düşük | Recent memory compact (5 alan), search sonuçları limitli |

## Notes

- **Phase 1-3 Supabase'siz çalışır** — dosya sistemi yeterli, Supabase opsiyonel
- **Geriye uyumluluk**: Mevcut MEMORY.md + project memory dosyaları korunur, yeni sistem bunların üzerine eklenir
- **Incremental adoption**: Her phase bağımsız değer sağlar, hepsini birden implement etmek zorunlu değil
- **Mio'dan farkımız**: Biz LLM API çağırmıyoruz (Mio Haiku çağırıyor), bunun yerine Claude Code'un kendi zekasını kullanıyoruz — daha ucuz, daha basit
- `pg_vector` extension'ı şimdilik gerekli değil — `pg_trgm` trigram search + full-text search başlangıç için yeterli. İhtiyaç duyulursa Phase 4'e embedding eklenebilir
