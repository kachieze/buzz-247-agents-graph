import fs from "node:fs";
import path from "node:path";

export function jailRoot() {
  const raw = process.env.MCP_FS_ROOT || process.env.HOME;
  if (!raw) {
    throw new Error("MCP_FS_ROOT or HOME must be set");
  }
  return fs.realpathSync(path.resolve(raw));
}

/**
 * Resolve userPath inside the jail. Rejects `..` escapes and symlink hops
 * that leave the root (so `/agents/alpha` cannot read `/agents/beta`).
 */
export function jail(userPath, root = jailRoot()) {
  if (typeof userPath !== "string" || userPath.length === 0) {
    throw new Error("path required");
  }
  const rootReal = fs.realpathSync(path.resolve(root));
  const candidate = path.resolve(rootReal, userPath);
  let real;
  try {
    real = fs.realpathSync(candidate);
  } catch {
    const parent = path.dirname(candidate);
    const parentReal = fs.realpathSync(parent);
    real = path.resolve(parentReal, path.basename(candidate));
  }
  const prefix = rootReal.endsWith(path.sep) ? rootReal : rootReal + path.sep;
  if (real !== rootReal && !real.startsWith(prefix)) {
    throw new Error("path escapes jail");
  }
  return real;
}
