#!/usr/bin/env node

/**
 * Calyx Browser MCP Server
 * Wraps the `calyx browser` CLI commands as MCP tools for Claude Code.
 */

import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  CallToolRequestSchema,
  ListToolsRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { execFileSync } from "child_process";
import { existsSync } from "fs";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const CALYX_BIN = "/Applications/Calyx.app/Contents/Resources/bin/calyx";

function runCalyx(args) {
  if (!existsSync(CALYX_BIN)) {
    throw new Error(
      "Calyx not found at " + CALYX_BIN + ". Install from https://github.com/yuuichieguchi/Calyx"
    );
  }
  try {
    return execFileSync(CALYX_BIN, ["browser", ...args], {
      encoding: "utf-8",
      timeout: 30_000,
    }).trim();
  } catch (err) {
    return (err.stdout || err.stderr || err.message || "").trim();
  }
}

// ---------------------------------------------------------------------------
// Tool definitions
// ---------------------------------------------------------------------------

const TOOLS = [
  {
    name: "browser_list",
    description: "List all open browser tabs in Calyx",
    inputSchema: { type: "object", properties: {} },
  },
  {
    name: "browser_open",
    description: "Open a new browser tab with the given URL",
    inputSchema: {
      type: "object",
      properties: {
        url: { type: "string", description: "URL to open" },
      },
      required: ["url"],
    },
  },
  {
    name: "browser_navigate",
    description: "Navigate a browser tab to a URL",
    inputSchema: {
      type: "object",
      properties: {
        url: { type: "string", description: "URL to navigate to" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["url"],
    },
  },
  {
    name: "browser_snapshot",
    description: "Get an accessibility snapshot of the page (DOM tree with element refs like @e1, @e2)",
    inputSchema: {
      type: "object",
      properties: {
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
    },
  },
  {
    name: "browser_screenshot",
    description: "Take a screenshot of the current page",
    inputSchema: {
      type: "object",
      properties: {
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
    },
  },
  {
    name: "browser_click",
    description: "Click an element by CSS selector",
    inputSchema: {
      type: "object",
      properties: {
        selector: { type: "string", description: "CSS selector of the element to click" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["selector"],
    },
  },
  {
    name: "browser_fill",
    description: "Fill an input field with a value",
    inputSchema: {
      type: "object",
      properties: {
        selector: { type: "string", description: "CSS selector of the input" },
        value: { type: "string", description: "Value to fill" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["selector", "value"],
    },
  },
  {
    name: "browser_type",
    description: "Type text into the focused element",
    inputSchema: {
      type: "object",
      properties: {
        text: { type: "string", description: "Text to type" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["text"],
    },
  },
  {
    name: "browser_press",
    description: "Press a keyboard key (e.g. Enter, Tab, Escape)",
    inputSchema: {
      type: "object",
      properties: {
        key: { type: "string", description: "Key to press" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["key"],
    },
  },
  {
    name: "browser_get_text",
    description: "Get the text content of an element",
    inputSchema: {
      type: "object",
      properties: {
        selector: { type: "string", description: "CSS selector" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["selector"],
    },
  },
  {
    name: "browser_get_html",
    description: "Get the HTML content of an element",
    inputSchema: {
      type: "object",
      properties: {
        selector: { type: "string", description: "CSS selector" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["selector"],
    },
  },
  {
    name: "browser_eval",
    description: "Evaluate JavaScript code in the page context",
    inputSchema: {
      type: "object",
      properties: {
        code: { type: "string", description: "JavaScript code to evaluate" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["code"],
    },
  },
  {
    name: "browser_wait",
    description: "Wait for a condition (selector to appear, timeout, etc.)",
    inputSchema: {
      type: "object",
      properties: {
        selector: { type: "string", description: "CSS selector to wait for" },
        timeout: { type: "number", description: "Timeout in ms (default: 5000)" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["selector"],
    },
  },
  {
    name: "browser_scroll",
    description: "Scroll the page or an element",
    inputSchema: {
      type: "object",
      properties: {
        direction: { type: "string", enum: ["up", "down", "left", "right"], description: "Scroll direction" },
        amount: { type: "number", description: "Scroll amount in pixels (default: 500)" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["direction"],
    },
  },
  {
    name: "browser_hover",
    description: "Hover over an element",
    inputSchema: {
      type: "object",
      properties: {
        selector: { type: "string", description: "CSS selector" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["selector"],
    },
  },
  {
    name: "browser_get_links",
    description: "Get all links on the page (returns JSON array)",
    inputSchema: {
      type: "object",
      properties: {
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
    },
  },
  {
    name: "browser_get_inputs",
    description: "Get all form inputs on the page (returns JSON array)",
    inputSchema: {
      type: "object",
      properties: {
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
    },
  },
  {
    name: "browser_is_visible",
    description: "Check if an element is visible on the page",
    inputSchema: {
      type: "object",
      properties: {
        selector: { type: "string", description: "CSS selector" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["selector"],
    },
  },
  {
    name: "browser_get_attribute",
    description: "Get an attribute value from an element",
    inputSchema: {
      type: "object",
      properties: {
        selector: { type: "string", description: "CSS selector" },
        attribute: { type: "string", description: "Attribute name" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["selector", "attribute"],
    },
  },
  {
    name: "browser_select",
    description: "Select an option from a dropdown",
    inputSchema: {
      type: "object",
      properties: {
        selector: { type: "string", description: "CSS selector of the select element" },
        value: { type: "string", description: "Option value to select" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["selector", "value"],
    },
  },
  {
    name: "browser_check",
    description: "Check a checkbox",
    inputSchema: {
      type: "object",
      properties: {
        selector: { type: "string", description: "CSS selector of the checkbox" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["selector"],
    },
  },
  {
    name: "browser_uncheck",
    description: "Uncheck a checkbox",
    inputSchema: {
      type: "object",
      properties: {
        selector: { type: "string", description: "CSS selector of the checkbox" },
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
      required: ["selector"],
    },
  },
  {
    name: "browser_back",
    description: "Navigate back in browser history",
    inputSchema: {
      type: "object",
      properties: {
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
    },
  },
  {
    name: "browser_forward",
    description: "Navigate forward in browser history",
    inputSchema: {
      type: "object",
      properties: {
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
    },
  },
  {
    name: "browser_reload",
    description: "Reload the current page",
    inputSchema: {
      type: "object",
      properties: {
        tab_id: { type: "string", description: "Tab ID (uses active tab if omitted)" },
      },
    },
  },
];

// ---------------------------------------------------------------------------
// Tool handlers
// ---------------------------------------------------------------------------

function buildTabArgs(tab_id) {
  return tab_id ? ["--tab-id", tab_id] : [];
}

const HANDLERS = {
  browser_list: () => runCalyx(["list"]),

  browser_open: ({ url }) => runCalyx(["open", url]),

  browser_navigate: ({ url, tab_id }) =>
    runCalyx(["navigate", url, ...buildTabArgs(tab_id)]),

  browser_snapshot: ({ tab_id }) =>
    runCalyx(["snapshot", ...buildTabArgs(tab_id)]),

  browser_screenshot: ({ tab_id }) =>
    runCalyx(["screenshot", ...buildTabArgs(tab_id)]),

  browser_click: ({ selector, tab_id }) =>
    runCalyx(["click", selector, ...buildTabArgs(tab_id)]),

  browser_fill: ({ selector, value, tab_id }) =>
    runCalyx(["fill", selector, "--value", value, ...buildTabArgs(tab_id)]),

  browser_type: ({ text, tab_id }) =>
    runCalyx(["type", text, ...buildTabArgs(tab_id)]),

  browser_press: ({ key, tab_id }) =>
    runCalyx(["press", key, ...buildTabArgs(tab_id)]),

  browser_get_text: ({ selector, tab_id }) =>
    runCalyx(["get-text", selector, ...buildTabArgs(tab_id)]),

  browser_get_html: ({ selector, tab_id }) =>
    runCalyx(["get-html", selector, ...buildTabArgs(tab_id)]),

  browser_eval: ({ code, tab_id }) =>
    runCalyx(["eval", code, ...buildTabArgs(tab_id)]),

  browser_wait: ({ selector, timeout, tab_id }) => {
    const args = ["wait", "--selector", selector];
    if (timeout) args.push("--timeout", String(timeout));
    args.push(...buildTabArgs(tab_id));
    return runCalyx(args);
  },

  browser_scroll: ({ direction, amount, tab_id }) => {
    const args = ["scroll", direction];
    if (amount) args.push("--amount", String(amount));
    args.push(...buildTabArgs(tab_id));
    return runCalyx(args);
  },

  browser_hover: ({ selector, tab_id }) =>
    runCalyx(["hover", selector, ...buildTabArgs(tab_id)]),

  browser_get_links: ({ tab_id }) =>
    runCalyx(["get-links", ...buildTabArgs(tab_id)]),

  browser_get_inputs: ({ tab_id }) =>
    runCalyx(["get-inputs", ...buildTabArgs(tab_id)]),

  browser_is_visible: ({ selector, tab_id }) =>
    runCalyx(["is-visible", selector, ...buildTabArgs(tab_id)]),

  browser_get_attribute: ({ selector, attribute, tab_id }) =>
    runCalyx(["get-attribute", selector, attribute, ...buildTabArgs(tab_id)]),

  browser_select: ({ selector, value, tab_id }) =>
    runCalyx(["select", selector, "--value", value, ...buildTabArgs(tab_id)]),

  browser_check: ({ selector, tab_id }) =>
    runCalyx(["check", selector, ...buildTabArgs(tab_id)]),

  browser_uncheck: ({ selector, tab_id }) =>
    runCalyx(["uncheck", selector, ...buildTabArgs(tab_id)]),

  browser_back: ({ tab_id }) =>
    runCalyx(["back", ...buildTabArgs(tab_id)]),

  browser_forward: ({ tab_id }) =>
    runCalyx(["forward", ...buildTabArgs(tab_id)]),

  browser_reload: ({ tab_id }) =>
    runCalyx(["reload", ...buildTabArgs(tab_id)]),
};

// ---------------------------------------------------------------------------
// Server setup
// ---------------------------------------------------------------------------

const server = new Server(
  { name: "calyx-browser", version: "1.0.0" },
  { capabilities: { tools: {} } }
);

server.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: TOOLS,
}));

server.setRequestHandler(CallToolRequestSchema, async (request) => {
  const { name, arguments: args } = request.params;

  const handler = HANDLERS[name];
  if (!handler) {
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({ error: `Unknown tool: ${name}` }),
        },
      ],
      isError: true,
    };
  }

  try {
    const result = handler(args || {});
    return {
      content: [{ type: "text", text: typeof result === "string" ? result : JSON.stringify(result, null, 2) }],
    };
  } catch (err) {
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({ error: err.message }),
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
  const transport = new StdioServerTransport();
  await server.connect(transport);
}

main().catch((err) => {
  console.error("Calyx Browser MCP server failed to start:", err);
  process.exit(1);
});
