import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";
import { test } from "node:test";
import { jail } from "./jail.mjs";

test("allows paths inside the jail", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "mcp-jail-alpha-"));
  fs.writeFileSync(path.join(root, "note.txt"), "ok");
  const abs = jail("note.txt", root);
  assert.equal(abs, path.join(fs.realpathSync(root), "note.txt"));
});

test("rejects ../beta escape", () => {
  const parent = fs.mkdtempSync(path.join(os.tmpdir(), "mcp-jail-parent-"));
  const alpha = path.join(parent, "alpha");
  const beta = path.join(parent, "beta");
  fs.mkdirSync(alpha);
  fs.mkdirSync(beta);
  fs.writeFileSync(path.join(beta, "secret.txt"), "nope");
  assert.throws(() => jail("../beta/secret.txt", alpha), /escapes jail/);
  assert.throws(() => jail("..", alpha), /escapes jail/);
});

test("rejects absolute paths outside the jail", () => {
  const root = fs.mkdtempSync(path.join(os.tmpdir(), "mcp-jail-abs-"));
  assert.throws(() => jail("/etc/passwd", root), /escapes jail/);
});
