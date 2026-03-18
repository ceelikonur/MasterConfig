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
  appendFileSync,
  readdirSync,
} from "fs";
import { join } from "path";
import { homedir } from "os";
import { randomUUID } from "crypto";

// ---------------------------------------------------------------------------
// Paths
// ---------------------------------------------------------------------------

const STATE_DIR = join(homedir(), ".claude", "orchestrator");
const MESSAGES_DIR = join(STATE_DIR, "messages");
const STATE_FILE = join(STATE_DIR, "state.json");
const TASKS_FILE = join(STATE_DIR, "tasks.json");

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function ensureDirs() {
  mkdirSync(STATE_DIR, { recursive: true });
  mkdirSync(MESSAGES_DIR, { recursive: true });
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

const HANDLER_MAP = {
  task_post: handleTaskPost,
  task_list: handleTaskList,
  task_update: handleTaskUpdate,
  message_send: handleMessageSend,
  message_read: handleMessageRead,
  team_info: handleTeamInfo,
};

// ---------------------------------------------------------------------------
// Server setup
// ---------------------------------------------------------------------------

const server = new Server(
  { name: "orchestrator", version: "3.0.0" },
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
