#!/usr/bin/env node

/**
 * Task Watcher v2 — monitors tasks.json and inbox files for changes,
 * then types notifications into the correct iTerm session via TTY matching.
 *
 * Flow: file change → find agent PID → get TTY → find iTerm session by TTY → type message
 */

import { watch, readFileSync, writeFileSync, existsSync, readdirSync } from "fs";
import { join } from "path";
import { homedir } from "os";
import { execSync } from "child_process";

const STATE_DIR = join(homedir(), ".claude", "orchestrator");
const TASKS_FILE = join(STATE_DIR, "tasks.json");
const STATE_FILE = join(STATE_DIR, "state.json");
const MESSAGES_DIR = join(STATE_DIR, "messages");

// Track what we've already notified about
const notifiedTaskIds = new Set();
const notifiedMessageIds = new Set();
let lastTasksContent = "";
const inboxSizes = new Map();

// ── Logging ───────────────────────────────────────────────────

function log(msg) {
  const ts = new Date().toISOString().slice(11, 19);
  const line = `[watcher ${ts}] ${msg}\n`;
  process.stderr.write(line);
  try {
    const logPath = join(STATE_DIR, "watcher.log");
    const { appendFileSync } = require("fs");
    appendFileSync(logPath, line);
  } catch {}
}

// ── TTY Resolution ────────────────────────────────────────────

/**
 * Find the TTY for a given PID
 */
function getTtyForPid(pid) {
  try {
    const tty = execSync(`ps -p ${pid} -o tty= 2>/dev/null`, { encoding: "utf-8" }).trim();
    if (!tty || tty === "??") return null;
    return `/dev/${tty}`;
  } catch {
    return null;
  }
}

/**
 * Get agent PID → TTY mapping from state.json
 */
function getAgentTtyMap() {
  const map = new Map(); // agentName → tty

  if (!existsSync(STATE_FILE)) return map;

  try {
    const state = JSON.parse(readFileSync(STATE_FILE, "utf-8"));

    // Lead agent
    if (state.leadAgentPID) {
      const tty = getTtyForPid(state.leadAgentPID);
      if (tty) map.set("lead", tty);
    }

    // Sub-agents
    for (const agent of state.agents || []) {
      if (agent.processRef) {
        const tty = getTtyForPid(agent.processRef);
        if (tty) map.set(agent.name, tty);
      }
    }
  } catch {}

  return map;
}

/**
 * Type text into an iTerm session identified by its TTY
 */
function typeIntoTty(tty, text) {
  const safe = text
    .replace(/\\/g, "\\\\")
    .replace(/"/g, '\\"')
    .replace(/\n/g, "\\n");

  const script = `
tell application "iTerm"
  repeat with w in windows
    repeat with t in tabs of w
      repeat with s in sessions of t
        if tty of s is "${tty}" then
          tell s
            write text "${safe}"
          end tell
          return "OK"
        end if
      end repeat
    end repeat
  end repeat
  return "NOT_FOUND"
end tell`;

  try {
    const result = execSync(`osascript -e '${script.replace(/'/g, "'\\''")}'`, {
      timeout: 5000,
      encoding: "utf-8",
    }).trim();
    return result === "OK";
  } catch {
    return false;
  }
}

/**
 * Type text to a named agent (resolves name → PID → TTY → iTerm session)
 */
function typeToAgent(agentName, text) {
  const ttyMap = getAgentTtyMap();
  const tty = ttyMap.get(agentName);

  if (!tty) {
    log(`No TTY found for agent ${agentName}`);
    return false;
  }

  const ok = typeIntoTty(tty, text);
  if (ok) {
    log(`Delivered to ${agentName} (${tty})`);
  } else {
    log(`Failed to deliver to ${agentName} (${tty})`);
  }
  return ok;
}

// ── Task board watcher ────────────────────────────────────────

function checkTasks() {
  if (!existsSync(TASKS_FILE)) return;

  let raw;
  try {
    raw = readFileSync(TASKS_FILE, "utf-8");
  } catch { return; }

  if (raw === lastTasksContent) return;
  lastTasksContent = raw;

  let tasks;
  try {
    tasks = JSON.parse(raw);
  } catch { return; }

  // Notify agents about new pending tasks
  for (const task of tasks) {
    if (task.status !== "pending") continue;
    if (notifiedTaskIds.has(task.id)) continue;

    notifiedTaskIds.add(task.id);
    log(`New task [${task.id}] for ${task.assignee}: ${task.title}`);

    // IMPORTANT: single line only! Multi-line text triggers Claude Code's "pasted text" mode which waits for Enter.
    const desc = task.description.replace(/\n/g, " ").replace(/\s+/g, " ").slice(0, 500);
    const notification = `NEW TASK [${task.id}] "${task.title}": ${desc} — Start: task_update(task_id:"${task.id}", status:"in_progress", updated_by:"${task.assignee}"), do the work, then task_update(task_id:"${task.id}", status:"completed", result:"<summary>", updated_by:"${task.assignee}")`;

    typeToAgent(task.assignee, notification);
  }

  // Notify lead about completed/failed tasks
  for (const task of tasks) {
    const doneKey = `done-${task.id}`;
    if (task.status !== "completed" && task.status !== "failed") continue;
    if (notifiedTaskIds.has(doneKey)) continue;

    notifiedTaskIds.add(doneKey);
    log(`Task [${task.id}] ${task.status} by ${task.assignee}`);

    // Single line to avoid Claude Code paste mode
    const resultStr = task.result ? ` Result: ${task.result.replace(/\n/g, " ")}` : "";
    const notification = `TASK ${task.status.toUpperCase()} [${task.id}] "${task.title}" by ${task.assignee}.${resultStr} — Check task_list for remaining tasks.`;

    typeToAgent("lead", notification);
  }
}

// ── Inbox watcher ─────────────────────────────────────────────

function checkInboxes() {
  if (!existsSync(MESSAGES_DIR)) return;

  let agents;
  try {
    agents = readdirSync(MESSAGES_DIR, { withFileTypes: true })
      .filter((d) => d.isDirectory())
      .map((d) => d.name);
  } catch { return; }

  for (const agentName of agents) {
    const inboxPath = join(MESSAGES_DIR, agentName, "inbox.jsonl");
    if (!existsSync(inboxPath)) continue;

    let raw;
    try { raw = readFileSync(inboxPath, "utf-8"); } catch { continue; }

    const lines = raw.split("\n").filter((l) => l.trim());
    const prevSize = inboxSizes.get(agentName) || 0;
    if (lines.length <= prevSize) continue;
    inboxSizes.set(agentName, lines.length);

    const newLines = lines.slice(prevSize);
    for (const line of newLines) {
      let msg;
      try { msg = JSON.parse(line); } catch { continue; }
      if (notifiedMessageIds.has(msg.id)) continue;
      notifiedMessageIds.add(msg.id);

      // Skip auto-notifications from task_post (handled by task watcher)
      if (msg.content && msg.content.startsWith("NEW TASK [")) continue;

      log(`New message for ${agentName} from ${msg.from}`);
      // Single line to avoid paste mode
      const content = (msg.content || "").replace(/\n/g, " ").slice(0, 500);
      typeToAgent(agentName, `Message from ${msg.from}: ${content}`);
    }
  }
}

// ── Initial state ─────────────────────────────────────────────

log("Task watcher v2 started (TTY-based)");

// Mark existing items as already notified
if (existsSync(TASKS_FILE)) {
  try {
    lastTasksContent = readFileSync(TASKS_FILE, "utf-8");
    const tasks = JSON.parse(lastTasksContent);
    for (const t of tasks) {
      notifiedTaskIds.add(t.id);
      if (t.status === "completed" || t.status === "failed") {
        notifiedTaskIds.add(`done-${t.id}`);
      }
    }
    log(`Initial scan: ${tasks.length} existing tasks`);
  } catch {}
}

if (existsSync(MESSAGES_DIR)) {
  try {
    const agents = readdirSync(MESSAGES_DIR, { withFileTypes: true })
      .filter((d) => d.isDirectory()).map((d) => d.name);
    for (const a of agents) {
      const inboxPath = join(MESSAGES_DIR, a, "inbox.jsonl");
      if (existsSync(inboxPath)) {
        const lines = readFileSync(inboxPath, "utf-8").split("\n").filter((l) => l.trim());
        inboxSizes.set(a, lines.length);
        for (const line of lines) {
          try { const m = JSON.parse(line); if (m.id) notifiedMessageIds.add(m.id); } catch {}
        }
      }
    }
  } catch {}
}

// ── File watchers ─────────────────────────────────────────────

if (existsSync(TASKS_FILE)) {
  watch(TASKS_FILE, () => setTimeout(checkTasks, 200));
  log(`Watching ${TASKS_FILE}`);
}

if (existsSync(MESSAGES_DIR)) {
  watch(MESSAGES_DIR, { recursive: true }, (event, filename) => {
    if (filename && filename.endsWith("inbox.jsonl")) {
      setTimeout(checkInboxes, 200);
    }
  });
  log(`Watching ${MESSAGES_DIR}`);
}

// Fallback periodic check every 60s
setInterval(() => {
  checkTasks();
  checkInboxes();
}, 60000);

log("Ready — watching for changes...");

process.on("SIGTERM", () => { log("Shutting down"); process.exit(0); });
process.on("SIGINT", () => { log("Shutting down"); process.exit(0); });
