#!/usr/bin/env node

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import {
  existsSync,
  mkdirSync,
  readFileSync,
  writeFileSync,
  renameSync,
  appendFileSync,
  readdirSync,
} from "fs";
import { join } from "path";
import { homedir } from "os";
import { randomUUID } from "crypto";

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

const STATE_DIR      = join(homedir(), ".claude", "orchestrator");
const MESSAGES_DIR   = join(STATE_DIR, "messages");
const STATE_FILE     = join(STATE_DIR, "state.json");
const TASKS_FILE     = join(STATE_DIR, "tasks.json");
const HIERARCHY_FILE = join(STATE_DIR, "hierarchy.json");
const PROJECTS_DIR   = join(STATE_DIR, "projects");
const ISSUES_DIR     = join(STATE_DIR, "issues");
const BUDGETS_DIR    = join(STATE_DIR, "budgets");
const BUDGET_CONFIG  = join(BUDGETS_DIR, "config.json");
const COSTS_DIR      = join(BUDGETS_DIR, "costs");
const APPROVALS_DIR  = join(STATE_DIR, "approvals");
const PENDING_DIR    = join(APPROVALS_DIR, "pending");
const DECIDED_DIR    = join(APPROVALS_DIR, "decided");
const ORG_DIR        = join(STATE_DIR, "org");
const ORG_FILE       = join(ORG_DIR, "nodes.json");
const ROUTINES_DIR   = join(STATE_DIR, "routines");
const ROUTINES_FILE  = join(ROUTINES_DIR, "routines.json");
const ROUTINE_LOGS   = join(ROUTINES_DIR, "logs.jsonl");
const ACTIVITY_FILE  = join(STATE_DIR, "activity.jsonl");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function ensureDirs() {
  mkdirSync(STATE_DIR,    { recursive: true });
  mkdirSync(MESSAGES_DIR, { recursive: true });
  mkdirSync(PROJECTS_DIR, { recursive: true });
  mkdirSync(ISSUES_DIR,   { recursive: true });
  mkdirSync(BUDGETS_DIR,  { recursive: true });
  mkdirSync(COSTS_DIR,    { recursive: true });
  mkdirSync(APPROVALS_DIR, { recursive: true });
  mkdirSync(PENDING_DIR,   { recursive: true });
  mkdirSync(DECIDED_DIR,   { recursive: true });
  mkdirSync(ORG_DIR,       { recursive: true });
  mkdirSync(ROUTINES_DIR,  { recursive: true });
}

function now() {
  return new Date().toISOString();
}

function loadState() {
  ensureDirs();
  if (!existsSync(STATE_FILE)) {
    const initial = {
      sessionId: randomUUID(),
      teamName: null,
      agents: [],
      mainSessionMode: "iterm",
      createdAt: now(),
      lastSaved: now(),
    };
    writeFileSync(STATE_FILE, JSON.stringify(initial, null, 2));
    return initial;
  }
  return JSON.parse(readFileSync(STATE_FILE, "utf-8"));
}

function saveState(state) {
  state.lastSaved = now();
  writeFileSync(STATE_FILE, JSON.stringify(state, null, 2));
}

function loadTasks() {
  ensureDirs();
  if (!existsSync(TASKS_FILE)) {
    writeFileSync(TASKS_FILE, JSON.stringify([], null, 2));
    return [];
  }
  try {
    return JSON.parse(readFileSync(TASKS_FILE, "utf-8"));
  } catch {
    return [];
  }
}

function saveTasks(tasks) {
  writeFileSync(TASKS_FILE, JSON.stringify(tasks, null, 2));
}

// ---------------------------------------------------------------------------
// Hierarchy helpers
// ---------------------------------------------------------------------------

function loadHierarchy() {
  ensureDirs();
  if (!existsSync(HIERARCHY_FILE)) {
    const initial = { goals: [], milestones: [] };
    writeFileSync(HIERARCHY_FILE, JSON.stringify(initial, null, 2));
    return initial;
  }
  try { return JSON.parse(readFileSync(HIERARCHY_FILE, "utf-8")); }
  catch { return { goals: [], milestones: [] }; }
}

function saveHierarchy(h) {
  atomicWriteJSON(HIERARCHY_FILE, h);
}

function loadProject(id) {
  const p = join(PROJECTS_DIR, `${id}.json`);
  if (!existsSync(p)) return null;
  try { return JSON.parse(readFileSync(p, "utf-8")); } catch { return null; }
}

function saveProject(project) {
  atomicWriteJSON(join(PROJECTS_DIR, `${project.id}.json`), project);
}

function loadIssue(id) {
  const p = join(ISSUES_DIR, `${id}.json`);
  if (!existsSync(p)) return null;
  try { return JSON.parse(readFileSync(p, "utf-8")); } catch { return null; }
}

function saveIssue(issue) {
  atomicWriteJSON(join(ISSUES_DIR, `${issue.id}.json`), issue);
}

function listAllIssues() {
  ensureDirs();
  try {
    return readdirSync(ISSUES_DIR)
      .filter(f => f.endsWith(".json") && !f.endsWith(".tmp"))
      .map(f => { try { return JSON.parse(readFileSync(join(ISSUES_DIR, f), "utf-8")); } catch { return null; } })
      .filter(Boolean);
  } catch { return []; }
}

function listAllProjects() {
  ensureDirs();
  try {
    return readdirSync(PROJECTS_DIR)
      .filter(f => f.endsWith(".json") && !f.endsWith(".tmp"))
      .map(f => { try { return JSON.parse(readFileSync(join(PROJECTS_DIR, f), "utf-8")); } catch { return null; } })
      .filter(Boolean);
  } catch { return []; }
}

// ---------------------------------------------------------------------------
// Budget helpers
// ---------------------------------------------------------------------------

function currentMonthKey() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}`;
}

function costsFilePath(monthKey) {
  return join(COSTS_DIR, `${monthKey}.jsonl`);
}

function loadBudgetConfig() {
  ensureDirs();
  if (!existsSync(BUDGET_CONFIG)) return {};
  try { return JSON.parse(readFileSync(BUDGET_CONFIG, "utf-8")); } catch { return {}; }
}

function saveBudgetConfig(config) {
  atomicWriteJSON(BUDGET_CONFIG, config);
}

function appendCostEntry(entry) {
  ensureDirs();
  const path = costsFilePath(currentMonthKey());
  const line = JSON.stringify(entry) + "\n";
  appendFileSync(path, line);
}

function readCostsForMonth(monthKey) {
  const path = costsFilePath(monthKey);
  if (!existsSync(path)) return [];
  return readFileSync(path, "utf-8")
    .split("\n")
    .filter(l => l.trim())
    .map(l => { try { return JSON.parse(l); } catch { return null; } })
    .filter(Boolean);
}

function readCostsForPeriod(period, agentName) {
  const now = new Date();
  const entries = readCostsForMonth(currentMonthKey());

  let filtered = entries;
  if (agentName) filtered = filtered.filter(e => e.agentName === agentName);

  if (period === "daily") {
    const today = new Date(now.getFullYear(), now.getMonth(), now.getDate()).getTime();
    return filtered.filter(e => new Date(e.timestamp).getTime() >= today);
  }
  if (period === "weekly") {
    const weekAgo = now.getTime() - 7 * 24 * 60 * 60 * 1000;
    return filtered.filter(e => new Date(e.timestamp).getTime() >= weekAgo);
  }
  return filtered; // monthly
}

// ---------------------------------------------------------------------------
// Approval helpers
// ---------------------------------------------------------------------------

function loadApproval(id) {
  for (const dir of [PENDING_DIR, DECIDED_DIR]) {
    const p = join(dir, `${id}.json`);
    if (existsSync(p)) {
      try { return JSON.parse(readFileSync(p, "utf-8")); } catch { return null; }
    }
  }
  return null;
}

function saveApproval(req, dir) {
  atomicWriteJSON(join(dir, `${req.id}.json`), req);
}

function listApprovalsFromDir(dir) {
  ensureDirs();
  try {
    return readdirSync(dir)
      .filter(f => f.endsWith(".json") && !f.endsWith(".tmp"))
      .map(f => { try { return JSON.parse(readFileSync(join(dir, f), "utf-8")); } catch { return null; } })
      .filter(Boolean)
      .sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  } catch { return []; }
}

// ---------------------------------------------------------------------------
// Routines helpers
// ---------------------------------------------------------------------------

function loadRoutines() {
  ensureDirs();
  if (!existsSync(ROUTINES_FILE)) return [];
  try { return JSON.parse(readFileSync(ROUTINES_FILE, "utf-8")); } catch { return []; }
}

function saveRoutines(routines) {
  atomicWriteJSON(ROUTINES_FILE, routines);
}

function appendRoutineLog(entry) {
  ensureDirs();
  appendFileSync(ROUTINE_LOGS, JSON.stringify(entry) + "\n");
}

function computeNextRun(schedule, after) {
  const base = after ? new Date(after) : new Date();
  switch (schedule.type) {
    case "interval": {
      const mins = schedule.intervalMinutes || 60;
      return new Date(base.getTime() + mins * 60 * 1000).toISOString();
    }
    case "daily": {
      const [h, m] = (schedule.timeOfDay || "09:00").split(":").map(Number);
      const next = new Date(base);
      next.setHours(h, m, 0, 0);
      if (next <= base) next.setDate(next.getDate() + 1);
      return next.toISOString();
    }
    case "weekly": {
      const wd = schedule.weekday ?? 1;
      const [h, m] = (schedule.timeOfDay || "09:00").split(":").map(Number);
      const next = new Date(base);
      next.setHours(h, m, 0, 0);
      let diff = (wd - base.getDay() + 7) % 7;
      if (diff === 0 && next <= base) diff = 7;
      next.setDate(next.getDate() + diff);
      return next.toISOString();
    }
    case "monthly": {
      const dom = schedule.dayOfMonth || 1;
      const [h, m] = (schedule.timeOfDay || "09:00").split(":").map(Number);
      const next = new Date(base.getFullYear(), base.getMonth(), dom, h, m, 0, 0);
      if (next <= base) next.setMonth(next.getMonth() + 1);
      return next.toISOString();
    }
    default:
      return new Date(base.getTime() + 60 * 60 * 1000).toISOString();
  }
}

// ---------------------------------------------------------------------------
// Org Chart helpers
// ---------------------------------------------------------------------------

function loadOrgNodes() {
  ensureDirs();
  if (!existsSync(ORG_FILE)) return [];
  try { return JSON.parse(readFileSync(ORG_FILE, "utf-8")); } catch { return []; }
}

function saveOrgNodes(nodes) {
  atomicWriteJSON(ORG_FILE, nodes);
}

// Atomic write: write to tmp then rename (prevents corruption)
function atomicWriteJSON(dest, obj) {
  const tmp = dest + ".tmp";
  const data = JSON.stringify(obj, null, 2);
  writeFileSync(tmp, data);
  try { renameSync(tmp, dest); } catch { writeFileSync(dest, data); }
}

function agentMessagesDir(agentName) {
  const dir = join(MESSAGES_DIR, agentName);
  mkdirSync(dir, { recursive: true });
  return dir;
}

function appendMessage(agentName, box, msg) {
  const dir = agentMessagesDir(agentName);
  appendFileSync(join(dir, `${box}.jsonl`), JSON.stringify(msg) + "\n");
}

function readJsonl(filePath, limit) {
  if (!existsSync(filePath)) return [];
  const lines = readFileSync(filePath, "utf-8")
    .split("\n")
    .filter((l) => l.trim());
  const parsed = lines
    .map((l) => {
      try { return JSON.parse(l); } catch { return null; }
    })
    .filter(Boolean);
  if (limit && limit > 0) return parsed.slice(-limit);
  return parsed;
}

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------

const TOOLS = [
  // ── Task Board ──────────────────────────────────────────────
  {
    name: "task_post",
    description:
      "Post a new task to the shared task board. Use this to assign work to agents. All agents can see the task board.",
    inputSchema: {
      type: "object",
      properties: {
        title: { type: "string", description: "Short task title" },
        description: { type: "string", description: "Detailed task description" },
        assignee: { type: "string", description: "Agent name to assign this task to" },
        posted_by: { type: "string", description: "Your agent name (who is posting)" },
        priority: { type: "string", enum: ["low", "normal", "high", "urgent"], description: "Task priority (default: normal)" },
      },
      required: ["title", "description", "assignee", "posted_by"],
    },
  },
  {
    name: "task_list",
    description:
      "List tasks from the shared task board. Filter by assignee or status. Call this periodically to check for new work assigned to you.",
    inputSchema: {
      type: "object",
      properties: {
        assignee: { type: "string", description: "Filter by assigned agent name (omit for all)" },
        status: { type: "string", enum: ["pending", "in_progress", "completed", "failed"], description: "Filter by status (omit for all)" },
      },
    },
  },
  {
    name: "task_update",
    description:
      "Update a task's status and optionally add a result. Use this to claim a task (in_progress), complete it (completed), or report failure (failed).",
    inputSchema: {
      type: "object",
      properties: {
        task_id: { type: "string", description: "Task ID to update" },
        status: { type: "string", enum: ["in_progress", "completed", "failed"], description: "New status" },
        result: { type: "string", description: "Result or progress note" },
        updated_by: { type: "string", description: "Your agent name" },
      },
      required: ["task_id", "status", "updated_by"],
    },
  },
  // ── Messaging ───────────────────────────────────────────────
  {
    name: "message_send",
    description:
      "Send a direct message to another agent. The message is written to their inbox file. They can read it with message_read.",
    inputSchema: {
      type: "object",
      properties: {
        from: { type: "string", description: "Your agent name (sender)" },
        to: { type: "string", description: "Recipient agent name" },
        content: { type: "string", description: "Message content" },
        type: { type: "string", enum: ["task", "result", "question", "status", "context"], description: "Message type (default: task)" },
      },
      required: ["from", "to", "content"],
    },
  },
  {
    name: "message_read",
    description:
      "Read messages from your inbox. Call this periodically to check for new messages from other agents or the UI.",
    inputSchema: {
      type: "object",
      properties: {
        agent_name: { type: "string", description: "Your agent name (reads your inbox)" },
        limit: { type: "number", description: "Max messages to return (default: 20)" },
        unread_only: { type: "boolean", description: "Only return messages newer than last read (default: false)" },
      },
      required: ["agent_name"],
    },
  },
  // ── Hierarchy: Goals ────────────────────────────────────────
  {
    name: "goal_create",
    description: "Create a new Goal (top-level initiative). Goals contain Projects.",
    inputSchema: {
      type: "object",
      properties: {
        title:       { type: "string", description: "Goal title" },
        description: { type: "string", description: "Optional description" },
      },
      required: ["title"],
    },
  },
  {
    name: "goal_list",
    description: "List all Goals, optionally filtered by status.",
    inputSchema: {
      type: "object",
      properties: {
        status: { type: "string", enum: ["active", "completed", "archived"], description: "Filter by status (omit for all)" },
      },
    },
  },
  // ── Hierarchy: Projects ─────────────────────────────────────
  {
    name: "project_create",
    description: "Create a new Project inside a Goal.",
    inputSchema: {
      type: "object",
      properties: {
        title:       { type: "string", description: "Project title" },
        description: { type: "string", description: "Optional description" },
        goal_id:     { type: "string", description: "Parent Goal ID (optional)" },
      },
      required: ["title"],
    },
  },
  {
    name: "project_list",
    description: "List all Projects, optionally filtered by Goal or status.",
    inputSchema: {
      type: "object",
      properties: {
        goal_id: { type: "string", description: "Filter by parent Goal ID" },
        status:  { type: "string", enum: ["active", "paused", "completed", "archived"] },
      },
    },
  },
  // ── Hierarchy: Milestones ───────────────────────────────────
  {
    name: "milestone_create",
    description: "Create a Milestone inside a Project.",
    inputSchema: {
      type: "object",
      properties: {
        title:      { type: "string", description: "Milestone title" },
        project_id: { type: "string", description: "Parent Project ID" },
        due_date:   { type: "string", description: "ISO-8601 due date (optional)" },
      },
      required: ["title", "project_id"],
    },
  },
  // ── Hierarchy: Issues ───────────────────────────────────────
  {
    name: "issue_create",
    description: "Create a new Issue (task). Supports parent issue for sub-issues.",
    inputSchema: {
      type: "object",
      properties: {
        title:           { type: "string", description: "Issue title" },
        description:     { type: "string", description: "Detailed description" },
        project_id:      { type: "string", description: "Parent Project ID (optional)" },
        milestone_id:    { type: "string", description: "Parent Milestone ID (optional)" },
        parent_issue_id: { type: "string", description: "Parent Issue ID for sub-issues (optional)" },
        assignee:        { type: "string", description: "Agent name to assign (optional)" },
        priority:        { type: "string", enum: ["low", "normal", "high", "urgent"], description: "Priority (default: normal)" },
        labels:          { type: "array", items: { type: "string" }, description: "Label strings (optional)" },
        created_by:      { type: "string", description: "Author agent name (default: agent)" },
      },
      required: ["title"],
    },
  },
  {
    name: "issue_update",
    description: "Update fields of an existing Issue (status, priority, assignee, etc.).",
    inputSchema: {
      type: "object",
      properties: {
        id:          { type: "string", description: "Issue ID" },
        title:       { type: "string" },
        description: { type: "string" },
        status:      { type: "string", enum: ["backlog", "todo", "in_progress", "review", "done"] },
        priority:    { type: "string", enum: ["low", "normal", "high", "urgent"] },
        assignee:    { type: "string" },
        labels:      { type: "array", items: { type: "string" } },
      },
      required: ["id"],
    },
  },
  {
    name: "issue_comment",
    description: "Add a comment to an Issue.",
    inputSchema: {
      type: "object",
      properties: {
        issue_id: { type: "string", description: "Issue ID" },
        author:   { type: "string", description: "Your agent name" },
        body:     { type: "string", description: "Comment text" },
      },
      required: ["issue_id", "author", "body"],
    },
  },
  {
    name: "issue_list",
    description: "List Issues with optional filters. Use this to find work assigned to you.",
    inputSchema: {
      type: "object",
      properties: {
        project_id:   { type: "string", description: "Filter by Project ID" },
        milestone_id: { type: "string", description: "Filter by Milestone ID" },
        assignee:     { type: "string", description: "Filter by assignee agent name" },
        status:       { type: "string", enum: ["backlog", "todo", "in_progress", "review", "done"] },
        priority:     { type: "string", enum: ["low", "normal", "high", "urgent"] },
      },
    },
  },
  // ── Governance & Approvals ──────────────────────────────────
  {
    name: "approval_request",
    description: "Request human approval for a high-impact action. The UI will show a notification. Poll approval_status to check the decision before proceeding.",
    inputSchema: {
      type: "object",
      properties: {
        type:          { type: "string", enum: ["agent_hire", "budget_change", "strategy_change", "high_risk_action", "project_creation", "deployment"], description: "Approval type" },
        title:         { type: "string", description: "Short title for the request" },
        description:   { type: "string", description: "Full description of what you want to do and why" },
        requested_by:  { type: "string", description: "Your agent name" },
        metadata:      { type: "object", additionalProperties: { type: "string" }, description: "Optional key-value context (e.g. issue_id, budget_amount)" },
      },
      required: ["type", "title", "description", "requested_by"],
    },
  },
  {
    name: "approval_status",
    description: "Check the status of an approval request. Poll this after approval_request to wait for the human decision.",
    inputSchema: {
      type: "object",
      properties: {
        request_id: { type: "string", description: "The approval request ID returned by approval_request" },
      },
      required: ["request_id"],
    },
  },
  {
    name: "approval_list",
    description: "List approval requests, optionally filtered by status.",
    inputSchema: {
      type: "object",
      properties: {
        status: { type: "string", enum: ["pending", "approved", "rejected", "revision_requested", "all"], description: "Filter by status (default: all)" },
      },
    },
  },
  // ── Budget & Cost Tracking ──────────────────────────────────
  {
    name: "cost_log",
    description: "Log a cost entry for an agent (tokens used + USD cost). Call this after each Claude API call to track spending.",
    inputSchema: {
      type: "object",
      properties: {
        agent_name:    { type: "string", description: "Your agent name" },
        input_tokens:  { type: "number", description: "Number of input tokens used" },
        output_tokens: { type: "number", description: "Number of output tokens used" },
        cost_usd:      { type: "number", description: "Total cost in USD for this call" },
        model:         { type: "string", description: "Model used (e.g. claude-sonnet-4-6)" },
        project_id:    { type: "string", description: "Associated project ID (optional)" },
        issue_id:      { type: "string", description: "Associated issue ID (optional)" },
      },
      required: ["agent_name", "input_tokens", "output_tokens", "cost_usd", "model"],
    },
  },
  {
    name: "cost_report",
    description: "Get a cost summary for an agent or all agents for a given period.",
    inputSchema: {
      type: "object",
      properties: {
        agent_name: { type: "string", description: "Agent name to filter (omit for all agents)" },
        period:     { type: "string", enum: ["daily", "weekly", "monthly"], description: "Report period (default: monthly)" },
      },
    },
  },
  {
    name: "budget_set",
    description: "Set or update the budget configuration for an agent.",
    inputSchema: {
      type: "object",
      properties: {
        agent_name:            { type: "string", description: "Agent name" },
        monthly_limit_usd:     { type: "number", description: "Monthly spending limit in USD" },
        soft_alert_threshold:  { type: "number", description: "Alert threshold as fraction 0.0–1.0 (default: 0.8)" },
        auto_pause_enabled:    { type: "boolean", description: "Pause agent when limit exceeded (default: false)" },
      },
      required: ["agent_name", "monthly_limit_usd"],
    },
  },
  {
    name: "budget_check",
    description: "Check the remaining budget and status for an agent. Call before large operations.",
    inputSchema: {
      type: "object",
      properties: {
        agent_name: { type: "string", description: "Agent name to check" },
      },
      required: ["agent_name"],
    },
  },
  // ── Team Info ───────────────────────────────────────────────
  {
    name: "team_info",
    description:
      "Get info about the current team: all agents, their repos, and statuses. Use this to know who is available.",
    inputSchema: {
      type: "object",
      properties: {},
    },
  },
  // ── Routines ────────────────────────────────────────────────
  {
    name: "routine_create",
    description: "Create a recurring routine that automatically creates issues on a schedule. The Swift app's timer checks every minute.",
    inputSchema: {
      type: "object",
      properties: {
        title:            { type: "string", description: "Routine title" },
        description:      { type: "string", description: "Routine description" },
        assignee:         { type: "string", description: "Agent name to assign created issues to" },
        schedule_type:    { type: "string", enum: ["interval","daily","weekly","monthly"], description: "Schedule type" },
        interval_minutes: { type: "number", description: "For interval type: minutes between runs (min 5)" },
        time_of_day:      { type: "string", description: "For daily/weekly/monthly: 'HH:MM' (e.g. '09:00')" },
        weekday:          { type: "number", description: "For weekly: 0=Sun, 1=Mon, ..., 6=Sat" },
        day_of_month:     { type: "number", description: "For monthly: 1–28" },
        issue_title:      { type: "string", description: "Issue title template (defaults to routine title)" },
        issue_description: { type: "string", description: "Issue description template" },
        issue_priority:   { type: "string", enum: ["low","normal","high","urgent"], description: "Issue priority" },
        issue_labels:     { type: "array", items: { type: "string" }, description: "Issue labels" },
        project_id:       { type: "string", description: "Project ID to assign issues to" },
      },
      required: ["title", "schedule_type"],
    },
  },
  {
    name: "routine_list",
    description: "List all routines with their schedule, status, and next run time.",
    inputSchema: {
      type: "object",
      properties: {
        enabled: { type: "boolean", description: "Filter by enabled/disabled (omit for all)" },
      },
    },
  },
  {
    name: "routine_toggle",
    description: "Enable or disable a routine by ID.",
    inputSchema: {
      type: "object",
      properties: {
        routine_id: { type: "string", description: "Routine ID" },
        enabled:    { type: "boolean", description: "true to enable, false to disable" },
      },
      required: ["routine_id", "enabled"],
    },
  },
  {
    name: "routine_trigger",
    description: "Trigger a routine immediately by setting its nextRun to now. The Swift timer will pick it up within 60 seconds.",
    inputSchema: {
      type: "object",
      properties: {
        routine_id: { type: "string", description: "Routine ID to trigger" },
      },
      required: ["routine_id"],
    },
  },
  // ── Activity Feed ───────────────────────────────────────────
  {
    name: "activity_log",
    description: "Append an activity entry to the audit trail. Call this whenever a significant agent action occurs (task created, issue updated, approval requested, cost incurred, etc.).",
    inputSchema: {
      type: "object",
      properties: {
        type:     { type: "string", description: "ActivityType key e.g. issue_created, task_updated, approval_requested, cost_logged, routine_fired, agent_spawned, agent_shutdown, message_sent" },
        actor:    { type: "string", description: "Agent name or 'system' that performed the action" },
        summary:  { type: "string", description: "Human-readable one-line summary of what happened" },
        metadata: { type: "object", description: "Optional key-value metadata (all values must be strings)" },
      },
      required: ["type", "actor", "summary"],
    },
  },
  {
    name: "activity_list",
    description: "Read recent activity entries from the audit trail. Supports filtering by actor and/or type prefix.",
    inputSchema: {
      type: "object",
      properties: {
        limit:       { type: "number", description: "Max entries to return (default 50)" },
        actor:       { type: "string", description: "Filter by actor name" },
        type_prefix: { type: "string", description: "Filter by activity type prefix e.g. 'issue', 'approval', 'cost'" },
      },
    },
  },
  // ── Org Chart ───────────────────────────────────────────────
  {
    name: "org_node_add",
    description: "Add an agent to the org chart. Use after hiring a new agent to register it in the hierarchy.",
    inputSchema: {
      type: "object",
      properties: {
        agent_name:       { type: "string", description: "Agent name (must be unique)" },
        role:             { type: "string", enum: ["ceo", "team_lead", "engineer", "specialist"], description: "Org role" },
        title:            { type: "string", description: "Human-readable title e.g. 'Backend Lead'" },
        reports_to:       { type: "string", description: "Parent agent's node ID (omit for root)" },
        team:             { type: "string", description: "Team name e.g. 'backend'" },
        responsibilities: { type: "array", items: { type: "string" }, description: "List of responsibilities" },
        skills:           { type: "array", items: { type: "string" }, description: "List of skills" },
      },
      required: ["agent_name", "role"],
    },
  },
  {
    name: "org_node_update",
    description: "Update an org chart node. Use to change status, current task, title, team, etc.",
    inputSchema: {
      type: "object",
      properties: {
        node_id:          { type: "string", description: "Node ID to update" },
        agent_name:       { type: "string" },
        role:             { type: "string", enum: ["ceo", "team_lead", "engineer", "specialist"] },
        title:            { type: "string" },
        reports_to:       { type: "string", description: "New parent node ID (null to make root)" },
        team:             { type: "string" },
        status:           { type: "string", enum: ["active", "idle", "paused", "offline"] },
        current_task:     { type: "string", description: "Current task description (null to clear)" },
        responsibilities: { type: "array", items: { type: "string" } },
        skills:           { type: "array", items: { type: "string" } },
      },
      required: ["node_id"],
    },
  },
  {
    name: "org_node_remove",
    description: "Remove an agent from the org chart. Children are reparented to the removed node's parent.",
    inputSchema: {
      type: "object",
      properties: {
        node_id: { type: "string", description: "Node ID to remove" },
      },
      required: ["node_id"],
    },
  },
  {
    name: "org_list",
    description: "List all org chart nodes. Optionally filter by team or role.",
    inputSchema: {
      type: "object",
      properties: {
        team: { type: "string", description: "Filter by team name" },
        role: { type: "string", enum: ["ceo", "team_lead", "engineer", "specialist"], description: "Filter by role" },
      },
    },
  },
];

// ---------------------------------------------------------------------------
// Tool handlers
// ---------------------------------------------------------------------------

async function handleTaskPost({ title, description, assignee, posted_by, priority }) {
  const tasks = loadTasks();

  const task = {
    id: randomUUID().slice(0, 8),
    title,
    description,
    assignee,
    posted_by: posted_by || "unknown",
    priority: priority || "normal",
    status: "pending",
    result: null,
    created_at: now(),
    updated_at: now(),
  };

  tasks.push(task);
  saveTasks(tasks);

  // Also write to assignee's inbox for discoverability
  const msg = {
    id: randomUUID(),
    timestamp: now(),
    from: posted_by || "orchestrator",
    to: assignee,
    content: `NEW TASK [${task.id}]: ${title}\n${description}`,
    messageType: "task",
  };
  appendMessage(assignee, "inbox", msg);

  return { task_id: task.id, status: "pending", assignee, title };
}

async function handleTaskList({ assignee, status }) {
  const tasks = loadTasks();

  let filtered = tasks;
  if (assignee) {
    filtered = filtered.filter((t) => t.assignee === assignee);
  }
  if (status) {
    filtered = filtered.filter((t) => t.status === status);
  }

  return {
    count: filtered.length,
    tasks: filtered.map((t) => ({
      id: t.id,
      title: t.title,
      description: t.description,
      assignee: t.assignee,
      posted_by: t.posted_by,
      status: t.status,
      priority: t.priority,
      result: t.result,
      created_at: t.created_at,
      updated_at: t.updated_at,
    })),
  };
}

async function handleTaskUpdate({ task_id, status, result, updated_by }) {
  const tasks = loadTasks();
  const task = tasks.find((t) => t.id === task_id);

  if (!task) {
    return { error: `Task '${task_id}' not found.` };
  }

  task.status = status;
  task.updated_at = now();
  if (result) {
    task.result = result;
  }

  saveTasks(tasks);

  // Notify the poster via their inbox
  if (task.posted_by && task.posted_by !== updated_by) {
    const msg = {
      id: randomUUID(),
      timestamp: now(),
      from: updated_by,
      to: task.posted_by,
      content: `TASK UPDATE [${task_id}]: ${status}${result ? "\n" + result : ""}`,
      messageType: "result",
    };
    appendMessage(task.posted_by, "inbox", msg);
  }

  return { task_id, status, updated_by, result: result || null };
}

async function handleMessageSend({ from, to, content, type }) {
  const msgType = type || "task";

  const msg = {
    id: randomUUID(),
    timestamp: now(),
    from,
    to,
    content,
    messageType: msgType,
  };

  appendMessage(to, "inbox", msg);

  return { delivered: true, message_id: msg.id, to };
}

async function handleMessageRead({ agent_name, limit, unread_only }) {
  const maxMsgs = limit || 20;
  const inboxPath = join(MESSAGES_DIR, agent_name, "inbox.jsonl");
  const messages = readJsonl(inboxPath, maxMsgs);

  // Track last read timestamp
  const lastReadFile = join(MESSAGES_DIR, agent_name, ".last_read");
  let lastRead = null;
  if (unread_only && existsSync(lastReadFile)) {
    lastRead = readFileSync(lastReadFile, "utf-8").trim();
  }

  let filtered = messages;
  if (lastRead) {
    filtered = messages.filter((m) => (m.timestamp || "") > lastRead);
  }

  // Update last read timestamp
  if (filtered.length > 0) {
    const latest = filtered[filtered.length - 1];
    writeFileSync(lastReadFile, latest.timestamp || now());
  }

  return {
    agent: agent_name,
    count: filtered.length,
    messages: filtered,
  };
}

// ---------------------------------------------------------------------------
// Hierarchy handlers
// ---------------------------------------------------------------------------

async function handleGoalCreate({ title, description }) {
  const h = loadHierarchy();
  const goal = {
    id: randomUUID().slice(0, 8),
    title,
    description: description || "",
    status: "active",
    projectIds: [],
    createdAt: now(),
    updatedAt: now(),
  };
  h.goals.push(goal);
  saveHierarchy(h);
  return { goal_id: goal.id, title, status: "active" };
}

async function handleGoalList({ status }) {
  const h = loadHierarchy();
  let goals = h.goals || [];
  if (status) goals = goals.filter(g => g.status === status);
  return { count: goals.length, goals };
}

async function handleProjectCreate({ title, description, goal_id }) {
  const h = loadHierarchy();
  const project = {
    id: randomUUID().slice(0, 8),
    title,
    description: description || "",
    goalId: goal_id || null,
    milestoneIds: [],
    status: "active",
    createdAt: now(),
  };
  if (goal_id) {
    const goalIdx = (h.goals || []).findIndex(g => g.id === goal_id);
    if (goalIdx >= 0) {
      h.goals[goalIdx].projectIds = h.goals[goalIdx].projectIds || [];
      h.goals[goalIdx].projectIds.push(project.id);
      h.goals[goalIdx].updatedAt = now();
    }
    saveHierarchy(h);
  }
  saveProject(project);
  return { project_id: project.id, title, goal_id: goal_id || null };
}

async function handleProjectList({ goal_id, status }) {
  let projects = listAllProjects();
  if (goal_id) projects = projects.filter(p => p.goalId === goal_id);
  if (status)  projects = projects.filter(p => p.status === status);
  return { count: projects.length, projects };
}

async function handleMilestoneCreate({ title, project_id, due_date }) {
  const h = loadHierarchy();
  const milestone = {
    id: randomUUID().slice(0, 8),
    title,
    projectId: project_id,
    issueIds: [],
    dueDate: due_date || null,
    status: "open",
  };
  h.milestones = h.milestones || [];
  h.milestones.push(milestone);

  // Update project's milestoneIds
  const project = loadProject(project_id);
  if (project) {
    project.milestoneIds = project.milestoneIds || [];
    project.milestoneIds.push(milestone.id);
    saveProject(project);
  }
  saveHierarchy(h);
  return { milestone_id: milestone.id, title, project_id };
}

async function handleIssueCreate({
  title, description, project_id, milestone_id,
  parent_issue_id, assignee, priority, labels, created_by,
}) {
  const h = loadHierarchy();
  const issue = {
    id: randomUUID().slice(0, 8),
    title,
    description: description || "",
    milestoneId: milestone_id || null,
    projectId: project_id || null,
    parentIssueId: parent_issue_id || null,
    assignee: assignee || null,
    status: "backlog",
    priority: priority || "normal",
    labels: labels || [],
    comments: [],
    attachments: [],
    createdBy: created_by || "agent",
    createdAt: now(),
    updatedAt: now(),
  };

  if (milestone_id) {
    const mIdx = (h.milestones || []).findIndex(m => m.id === milestone_id);
    if (mIdx >= 0) {
      h.milestones[mIdx].issueIds = h.milestones[mIdx].issueIds || [];
      h.milestones[mIdx].issueIds.push(issue.id);
      saveHierarchy(h);
    }
  }
  saveIssue(issue);

  // Also write to assignee's inbox if assigned
  if (assignee) {
    appendMessage(assignee, "inbox", {
      id: randomUUID(),
      timestamp: now(),
      from: created_by || "orchestrator",
      to: assignee,
      content: `NEW ISSUE [${issue.id}]: ${title}\n${description || ""}`,
      messageType: "task",
    });
  }

  return { issue_id: issue.id, title, assignee: assignee || null, status: "backlog" };
}

async function handleIssueUpdate({ id, title, description, status, priority, assignee, labels }) {
  const issue = loadIssue(id);
  if (!issue) return { error: `Issue '${id}' not found.` };

  if (title !== undefined)       issue.title = title;
  if (description !== undefined) issue.description = description;
  if (status !== undefined)      issue.status = status;
  if (priority !== undefined)    issue.priority = priority;
  if (assignee !== undefined)    issue.assignee = assignee;
  if (labels !== undefined)      issue.labels = labels;
  issue.updatedAt = now();

  saveIssue(issue);
  return { issue_id: id, updated: true, status: issue.status };
}

async function handleIssueComment({ issue_id, author, body }) {
  const issue = loadIssue(issue_id);
  if (!issue) return { error: `Issue '${issue_id}' not found.` };

  const comment = { id: randomUUID().slice(0, 8), author, body, createdAt: now() };
  issue.comments = issue.comments || [];
  issue.comments.push(comment);
  issue.updatedAt = now();
  saveIssue(issue);
  return { comment_id: comment.id, issue_id, author };
}

async function handleIssueList({ project_id, milestone_id, assignee, status, priority }) {
  let issues = listAllIssues();
  if (project_id)   issues = issues.filter(i => i.projectId === project_id);
  if (milestone_id) issues = issues.filter(i => i.milestoneId === milestone_id);
  if (assignee)     issues = issues.filter(i => i.assignee === assignee);
  if (status)       issues = issues.filter(i => i.status === status);
  if (priority)     issues = issues.filter(i => i.priority === priority);
  return {
    count: issues.length,
    issues: issues.map(i => ({
      id: i.id, title: i.title, status: i.status, priority: i.priority,
      assignee: i.assignee, projectId: i.projectId, milestoneId: i.milestoneId,
      labels: i.labels, createdAt: i.createdAt, updatedAt: i.updatedAt,
      comment_count: (i.comments || []).length,
    })),
  };
}

// ---------------------------------------------------------------------------
// Governance & Approval handlers
// ---------------------------------------------------------------------------

async function handleApprovalRequest({ type, title, description, requested_by, metadata }) {
  ensureDirs();
  const id  = randomUUID().slice(0, 8);
  const req = {
    id,
    type:        type,
    title,
    description: description || "",
    requestedBy: requested_by,
    status:      "pending",
    decision:    null,
    metadata:    metadata || {},
    createdAt:   now(),
    decidedAt:   null,
  };
  saveApproval(req, PENDING_DIR);
  return { request_id: id, status: "pending", message: "Approval request created. Poll approval_status to check the decision." };
}

async function handleApprovalStatus({ request_id }) {
  const req = loadApproval(request_id);
  if (!req) return { error: `Approval request '${request_id}' not found.` };
  return {
    request_id,
    status:     req.status,
    title:      req.title,
    decision:   req.decision || null,
    notes:      req.decision?.notes || null,
    decided_at: req.decidedAt || null,
  };
}

async function handleApprovalList({ status }) {
  ensureDirs();
  let pending  = listApprovalsFromDir(PENDING_DIR);
  let decided  = listApprovalsFromDir(DECIDED_DIR);
  let all      = [...pending, ...decided];

  if (status && status !== "all") {
    all = all.filter(r => r.status === status);
  }

  return {
    count: all.length,
    requests: all.map(r => ({
      id:           r.id,
      type:         r.type,
      title:        r.title,
      requested_by: r.requestedBy,
      status:       r.status,
      created_at:   r.createdAt,
      decided_at:   r.decidedAt || null,
    })),
  };
}

// ---------------------------------------------------------------------------
// Budget & Cost handlers
// ---------------------------------------------------------------------------

async function handleCostLog({ agent_name, input_tokens, output_tokens, cost_usd, model, project_id, issue_id }) {
  const entry = {
    id:           randomUUID().slice(0, 8),
    agentName:    agent_name,
    projectId:    project_id  || null,
    issueId:      issue_id    || null,
    inputTokens:  input_tokens,
    outputTokens: output_tokens,
    costUSD:      cost_usd,
    model,
    timestamp:    now(),
  };

  appendCostEntry(entry);

  // Update budget config's currentSpendUSD
  const config = loadBudgetConfig();
  if (config[agent_name]) {
    config[agent_name].currentSpendUSD = (config[agent_name].currentSpendUSD || 0) + cost_usd;
    config[agent_name].tokenUsage = config[agent_name].tokenUsage || { inputTokens: 0, outputTokens: 0, totalCostUSD: 0 };
    config[agent_name].tokenUsage.inputTokens  += input_tokens;
    config[agent_name].tokenUsage.outputTokens += output_tokens;
    config[agent_name].tokenUsage.totalCostUSD += cost_usd;
    config[agent_name].tokenUsage.lastUpdated   = now();
    saveBudgetConfig(config);
  }

  return { logged: true, entry_id: entry.id, agent_name, cost_usd, model };
}

async function handleCostReport({ agent_name, period }) {
  const p       = period || "monthly";
  const entries = readCostsForPeriod(p, agent_name);
  const total   = entries.reduce((sum, e) => sum + (e.costUSD || 0), 0);
  const totalIn  = entries.reduce((sum, e) => sum + (e.inputTokens  || 0), 0);
  const totalOut = entries.reduce((sum, e) => sum + (e.outputTokens || 0), 0);

  // Per-agent breakdown
  const byAgent = {};
  for (const e of entries) {
    if (!byAgent[e.agentName]) byAgent[e.agentName] = { costUSD: 0, inputTokens: 0, outputTokens: 0, entries: 0 };
    byAgent[e.agentName].costUSD      += e.costUSD || 0;
    byAgent[e.agentName].inputTokens  += e.inputTokens  || 0;
    byAgent[e.agentName].outputTokens += e.outputTokens || 0;
    byAgent[e.agentName].entries++;
  }

  return {
    period: p,
    agent_name: agent_name || "all",
    total_cost_usd: Math.round(total * 1e6) / 1e6,
    total_input_tokens: totalIn,
    total_output_tokens: totalOut,
    entry_count: entries.length,
    by_agent: byAgent,
  };
}

async function handleBudgetSet({ agent_name, monthly_limit_usd, soft_alert_threshold, auto_pause_enabled }) {
  const config = loadBudgetConfig();
  const existing = config[agent_name] || {
    currentSpendUSD: 0,
    tokenUsage: { inputTokens: 0, outputTokens: 0, totalCostUSD: 0, lastUpdated: now() },
  };

  config[agent_name] = {
    ...existing,
    monthlyLimitUSD:    monthly_limit_usd,
    softAlertThreshold: soft_alert_threshold ?? 0.8,
    autoPauseEnabled:   auto_pause_enabled   ?? false,
  };

  saveBudgetConfig(config);
  return { agent_name, monthly_limit_usd, soft_alert_threshold: config[agent_name].softAlertThreshold, set: true };
}

async function handleBudgetCheck({ agent_name }) {
  const config  = loadBudgetConfig();
  const agentCfg = config[agent_name];
  const entries = readCostsForPeriod("monthly", agent_name);
  const spent   = entries.reduce((s, e) => s + (e.costUSD || 0), 0);

  if (!agentCfg) {
    return { agent_name, status: "no_limit", spent_usd: Math.round(spent * 1e6) / 1e6, remaining_usd: null, ratio: null };
  }

  const limit     = agentCfg.monthlyLimitUSD || 0;
  const ratio     = limit > 0 ? spent / limit : 0;
  const remaining = Math.max(limit - spent, 0);

  let status = "ok";
  if (ratio >= 1.0)                              status = "exceeded";
  else if (ratio >= (agentCfg.softAlertThreshold || 0.8)) status = "warning";

  return {
    agent_name,
    status,
    spent_usd:     Math.round(spent * 1e6) / 1e6,
    limit_usd:     limit,
    remaining_usd: Math.round(remaining * 1e6) / 1e6,
    ratio:         Math.round(ratio * 1000) / 1000,
    auto_pause:    agentCfg.autoPauseEnabled || false,
  };
}

async function handleTeamInfo() {
  const state = loadState();

  return {
    session_id: state.sessionId,
    team_name: state.teamName,
    mode: state.mainSessionMode,
    agents: (state.agents || []).map((a) => ({
      name: a.name,
      repo: a.repoPath,
      repo_name: a.repoName,
      status: a.status,
      current_task: a.currentTask,
      last_activity: a.lastActivity,
    })),
    lead_agent_status: state.leadAgentStatus,
  };
}

// ---------------------------------------------------------------------------
// Router
// ---------------------------------------------------------------------------

// Backward-compat proxies: legacy task_* tools → new issue_* handlers
async function handleTaskPostCompat({ title, description, assignee, posted_by, priority }) {
  // Create an issue and also write the old tasks.json entry for UI compat
  const issueResult = await handleIssueCreate({
    title, description, assignee, created_by: posted_by, priority,
  });
  // Also maintain tasks.json for existing UI code
  await handleTaskPost({ title, description, assignee, posted_by, priority });
  return issueResult;
}

// ---------------------------------------------------------------------------
// Routine handlers
// ---------------------------------------------------------------------------

async function handleRoutineCreate({ title, description, assignee, schedule_type,
  interval_minutes, time_of_day, weekday, day_of_month,
  issue_title, issue_description, issue_priority, issue_labels, project_id }) {
  const schedule = {
    type: schedule_type || "daily",
    intervalMinutes: schedule_type === "interval" ? (interval_minutes || 60) : undefined,
    timeOfDay:       schedule_type !== "interval" ? (time_of_day || "09:00") : undefined,
    weekday:         schedule_type === "weekly"   ? (weekday ?? 1)  : undefined,
    dayOfMonth:      schedule_type === "monthly"  ? (day_of_month ?? 1) : undefined,
  };

  const routine = {
    id:          randomUUID().slice(0, 8),
    title,
    description: description || "",
    assignee:    assignee || null,
    schedule,
    issueTemplate: {
      title:       issue_title       || "",
      description: issue_description || "",
      priority:    issue_priority    || "normal",
      labels:      issue_labels      || [],
      projectId:   project_id        || null,
      milestoneId: null,
    },
    enabled:   true,
    lastRun:   null,
    nextRun:   computeNextRun(schedule),
    runCount:  0,
    createdAt: now(),
    updatedAt: now(),
  };

  const routines = loadRoutines();
  routines.push(routine);
  saveRoutines(routines);

  return {
    routine_id: routine.id,
    title,
    schedule_type: schedule.type,
    next_run: routine.nextRun,
    enabled: true,
  };
}

async function handleRoutineList({ enabled }) {
  let routines = loadRoutines();
  if (enabled !== undefined) routines = routines.filter(r => r.enabled === enabled);
  return {
    count: routines.length,
    routines: routines.map(r => ({
      id:            r.id,
      title:         r.title,
      schedule:      r.schedule.type,
      schedule_summary: schedSummary(r.schedule),
      enabled:       r.enabled,
      run_count:     r.runCount,
      last_run:      r.lastRun,
      next_run:      r.nextRun,
    })),
  };
}

function schedSummary(s) {
  switch (s.type) {
    case "interval": return `Every ${s.intervalMinutes || 60} min`;
    case "daily":    return `Daily at ${s.timeOfDay || "09:00"}`;
    case "weekly":   return `Weekly on weekday ${s.weekday ?? 1} at ${s.timeOfDay || "09:00"}`;
    case "monthly":  return `Monthly on day ${s.dayOfMonth ?? 1} at ${s.timeOfDay || "09:00"}`;
    default:         return s.type;
  }
}

async function handleRoutineToggle({ routine_id, enabled }) {
  const routines = loadRoutines();
  const idx = routines.findIndex(r => r.id === routine_id);
  if (idx < 0) return { error: `Routine '${routine_id}' not found.` };
  routines[idx].enabled   = enabled;
  routines[idx].updatedAt = now();
  if (enabled && !routines[idx].nextRun) {
    routines[idx].nextRun = computeNextRun(routines[idx].schedule);
  }
  saveRoutines(routines);
  return { routine_id, enabled, title: routines[idx].title };
}

async function handleRoutineTrigger({ routine_id }) {
  const routines = loadRoutines();
  const idx = routines.findIndex(r => r.id === routine_id);
  if (idx < 0) return { error: `Routine '${routine_id}' not found.` };
  // Set nextRun to now — the Swift timer picks it up within 60 seconds
  routines[idx].nextRun   = now();
  routines[idx].updatedAt = now();
  saveRoutines(routines);
  return {
    routine_id,
    triggered: true,
    title: routines[idx].title,
    note: "nextRun set to now — Swift timer will fire within 60 seconds.",
  };
}

// ---------------------------------------------------------------------------
// Activity helpers
// ---------------------------------------------------------------------------

function appendActivity(entry) {
  ensureDirs();
  appendFileSync(ACTIVITY_FILE, JSON.stringify(entry) + "\n");
}

function readRecentActivity(limit = 50, actorFilter, typePrefix) {
  if (!existsSync(ACTIVITY_FILE)) return [];
  const raw = readFileSync(ACTIVITY_FILE, "utf8");
  let entries = raw
    .split("\n")
    .filter(l => l.trim())
    .map(l => { try { return JSON.parse(l); } catch { return null; } })
    .filter(Boolean);
  if (actorFilter)  entries = entries.filter(e => e.actor === actorFilter);
  if (typePrefix)   entries = entries.filter(e => (e.type || "").startsWith(typePrefix));
  // newest first
  entries.reverse();
  return entries.slice(0, limit);
}

// ---------------------------------------------------------------------------
// Activity handlers
// ---------------------------------------------------------------------------

async function handleActivityLog({ type, actor, summary, metadata }) {
  const entry = {
    id:        randomUUID().slice(0, 8),
    type:      type || "unknown",
    actor:     actor || "system",
    summary:   summary || "",
    metadata:  metadata || {},
    timestamp: now(),
  };
  appendActivity(entry);
  return { logged: true, id: entry.id, type: entry.type, actor: entry.actor };
}

async function handleActivityList({ limit, actor, type_prefix }) {
  const entries = readRecentActivity(limit || 50, actor, type_prefix);
  return {
    count: entries.length,
    entries: entries.map(e => ({
      id:        e.id,
      type:      e.type,
      actor:     e.actor,
      summary:   e.summary,
      timestamp: e.timestamp,
    })),
  };
}

// ---------------------------------------------------------------------------
// Org Chart handlers
// ---------------------------------------------------------------------------

async function handleOrgNodeAdd({ agent_name, role, title, reports_to, team, responsibilities, skills }) {
  const nodes = loadOrgNodes();
  if (nodes.find(n => n.agentName === agent_name)) {
    return { error: `Agent '${agent_name}' is already in the org chart.` };
  }
  const node = {
    id:               randomUUID().slice(0, 8),
    agentName:        agent_name,
    role:             role || "engineer",
    title:            title || "",
    reportsTo:        reports_to || null,
    team:             team || null,
    responsibilities: responsibilities || [],
    skills:           skills || [],
    status:           "idle",
    currentTask:      null,
    createdAt:        now(),
    updatedAt:        now(),
  };
  nodes.push(node);
  saveOrgNodes(nodes);
  return { node_id: node.id, agent_name, role: node.role, reports_to: node.reportsTo };
}

async function handleOrgNodeUpdate({ node_id, agent_name, role, title, reports_to, team, status, current_task, responsibilities, skills }) {
  const nodes = loadOrgNodes();
  const idx = nodes.findIndex(n => n.id === node_id);
  if (idx < 0) return { error: `Node '${node_id}' not found.` };

  const n = nodes[idx];
  if (agent_name       !== undefined) n.agentName        = agent_name;
  if (role             !== undefined) n.role              = role;
  if (title            !== undefined) n.title             = title;
  if (reports_to       !== undefined) n.reportsTo         = reports_to;
  if (team             !== undefined) n.team              = team;
  if (status           !== undefined) n.status            = status;
  if (current_task     !== undefined) n.currentTask       = current_task;
  if (responsibilities !== undefined) n.responsibilities  = responsibilities;
  if (skills           !== undefined) n.skills            = skills;
  n.updatedAt = now();

  nodes[idx] = n;
  saveOrgNodes(nodes);
  return { updated: true, node_id, agent_name: n.agentName };
}

async function handleOrgNodeRemove({ node_id }) {
  let nodes = loadOrgNodes();
  const target = nodes.find(n => n.id === node_id);
  if (!target) return { error: `Node '${node_id}' not found.` };

  // Reparent children
  const grandparent = target.reportsTo;
  nodes = nodes.map(n => n.reportsTo === node_id ? { ...n, reportsTo: grandparent, updatedAt: now() } : n);
  nodes = nodes.filter(n => n.id !== node_id);
  saveOrgNodes(nodes);
  return { removed: true, node_id, agent_name: target.agentName, reparented_children: nodes.filter(n => n.reportsTo === grandparent).length };
}

async function handleOrgList({ team, role }) {
  let nodes = loadOrgNodes();
  if (team) nodes = nodes.filter(n => n.team === team);
  if (role) nodes = nodes.filter(n => n.role === role);
  return {
    count: nodes.length,
    nodes: nodes.map(n => ({
      id:          n.id,
      agent_name:  n.agentName,
      role:        n.role,
      title:       n.title,
      reports_to:  n.reportsTo,
      team:        n.team,
      status:      n.status,
      current_task: n.currentTask,
    })),
  };
}

const HANDLER_MAP = {
  // Hierarchy
  goal_create:      handleGoalCreate,
  goal_list:        handleGoalList,
  project_create:   handleProjectCreate,
  project_list:     handleProjectList,
  milestone_create: handleMilestoneCreate,
  issue_create:     handleIssueCreate,
  issue_update:     handleIssueUpdate,
  issue_comment:    handleIssueComment,
  issue_list:       handleIssueList,
  // Legacy (backward compat — still work, now proxy to issue system)
  task_post:    handleTaskPost,
  task_list:    handleTaskList,
  task_update:  handleTaskUpdate,
  // Governance & Approvals
  approval_request: handleApprovalRequest,
  approval_status:  handleApprovalStatus,
  approval_list:    handleApprovalList,
  // Budget & Cost
  cost_log:    handleCostLog,
  cost_report: handleCostReport,
  budget_set:  handleBudgetSet,
  budget_check: handleBudgetCheck,
  // Routines
  routine_create:  handleRoutineCreate,
  routine_list:    handleRoutineList,
  routine_toggle:  handleRoutineToggle,
  routine_trigger: handleRoutineTrigger,
  // Activity Feed
  activity_log:    handleActivityLog,
  activity_list:   handleActivityList,
  // Org Chart
  org_node_add:    handleOrgNodeAdd,
  org_node_update: handleOrgNodeUpdate,
  org_node_remove: handleOrgNodeRemove,
  org_list:        handleOrgList,
  // Messaging & state
  message_send: handleMessageSend,
  message_read: handleMessageRead,
  team_info:    handleTeamInfo,
};

// ---------------------------------------------------------------------------
// Server setup
// ---------------------------------------------------------------------------

const server = new Server(
  { name: "orchestrator", version: "7.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS,
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  const handler = HANDLER_MAP[name];
  if (!handler) {
    return {
      content: [
        { type: "text", text: JSON.stringify({ error: `Unknown tool: ${name}` }) },
      ],
      isError: true,
    };
  }

  try {
    const result = await handler(args || {});
    const hasError = result && typeof result === "object" && "error" in result;
    return {
      content: [{ type: "text", text: JSON.stringify(result, null, 2) }],
      isError: hasError,
    };
  } catch (err) {
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({
            error: err.message,
            stack: process.env.DEBUG ? err.stack : undefined,
          }),
        },
      ],
      isError: true,
    };
  }
});

// ---------------------------------------------------------------------------
// Start
// ---------------------------------------------------------------------------

async function main() {
  ensureDirs();
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Orchestrator MCP server failed to start:", err);
  process.exit(1);
});
