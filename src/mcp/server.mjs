#!/usr/bin/env node
import { spawn } from "node:child_process";
import fs from "node:fs/promises";
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import { z } from "zod";
import { jail } from "./jail.mjs";

const server = new McpServer({
  name: "agent-plane-mcp",
  version: "1.0.0",
});

server.tool(
  "fs_list",
  "List a directory inside the agent HOME jail.",
  { path: z.string().default(".") },
  async ({ path: userPath }) => {
    const abs = jail(userPath);
    const names = await fs.readdir(abs);
    return { content: [{ type: "text", text: names.join("\n") }] };
  },
);

server.tool(
  "fs_stat",
  "Stat a file or directory inside the agent HOME jail.",
  { path: z.string() },
  async ({ path: userPath }) => {
    const abs = jail(userPath);
    const st = await fs.stat(abs);
    return {
      content: [
        {
          type: "text",
          text: JSON.stringify({
            path: abs,
            size: st.size,
            isFile: st.isFile(),
            isDirectory: st.isDirectory(),
            mtime: st.mtime.toISOString(),
          }),
        },
      ],
    };
  },
);

server.tool(
  "fs_read",
  "Read a UTF-8 file inside the agent HOME jail.",
  { path: z.string() },
  async ({ path: userPath }) => {
    const abs = jail(userPath);
    const text = await fs.readFile(abs, "utf8");
    return { content: [{ type: "text", text }] };
  },
);

server.tool(
  "fs_write",
  "Write a UTF-8 file inside the agent HOME jail. Creates parent dirs.",
  { path: z.string(), content: z.string() },
  async ({ path: userPath, content }) => {
    const abs = jail(userPath);
    await fs.mkdir(pathDir(abs), { recursive: true });
    await fs.writeFile(abs, content, { encoding: "utf8", mode: 0o640 });
    return { content: [{ type: "text", text: abs }] };
  },
);

server.tool(
  "github_pr",
  "Thin wrap of `gh pr`. App mode: gh auth + git credential helper (not a parent GH_TOKEN). PAT mode: GH_TOKEN from GITHUB_PAT.",
  {
    args: z.array(z.string()).min(1).describe("Arguments after `gh pr`"),
  },
  async ({ args }) => ({ content: [{ type: "text", text: await runGh(["pr", ...args]) }] }),
);

server.tool(
  "github_issue",
  "Thin wrap of `gh issue`.",
  { args: z.array(z.string()).min(1) },
  async ({ args }) => ({ content: [{ type: "text", text: await runGh(["issue", ...args]) }] }),
);

server.tool(
  "github_repo",
  "Thin wrap of `gh repo`.",
  { args: z.array(z.string()).min(1) },
  async ({ args }) => ({ content: [{ type: "text", text: await runGh(["repo", ...args]) }] }),
);

function pathDir(abs) {
  const i = abs.lastIndexOf("/");
  return i <= 0 ? "/" : abs.slice(0, i);
}

function runGh(args) {
  return new Promise((resolve, reject) => {
    const child = spawn("gh", args, { env: process.env });
    let out = "";
    let err = "";
    child.stdout.on("data", (c) => {
      out += c;
    });
    child.stderr.on("data", (c) => {
      err += c;
    });
    child.on("error", reject);
    child.on("close", (code) => {
      if (code === 0) resolve(out || "(ok)");
      else reject(new Error(err || `gh exited ${code}`));
    });
  });
}

const transport = new StdioServerTransport();
await server.connect(transport);
