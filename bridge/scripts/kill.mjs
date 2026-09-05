#!/usr/bin/env node
/**
 * pi Bridge - cross-platform process killer
 *
 * Kills the bridge no matter how it was started (dev:bridge or the
 * Windows scheduled-task service), plus any leftover process chains.
 *
 * Usage: npm run kill -w bridge        (or: node bridge/scripts/kill.mjs)
 * Env:   PI_CHROME_PORT (default 18731)
 */
import { execSync, spawnSync } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const port = process.env.PI_CHROME_PORT || "18731";
const scriptDir = path.dirname(fileURLToPath(import.meta.url));

if (process.platform === "win32") {
  // Delegate to stop-bridge.ps1: kills the service task, the port listener,
  // and orphaned npm/tsx dev chains (taskkill /T /F).
  const ps1 = path.join(scriptDir, "stop-bridge.ps1");
  const result = spawnSync(
    "powershell",
    ["-NoProfile", "-ExecutionPolicy", "Bypass", "-File", ps1, "-Port", String(port)],
    { stdio: "inherit" },
  );
  process.exit(result.status ?? 1);
} else {
  // Unix: fuser first (matches the old behavior), fall back to lsof.
  try {
    execSync(`fuser -k ${port}/tcp 2>/dev/null`, { stdio: "inherit" });
    console.log("Bridge killed");
  } catch {
    try {
      const pids = execSync(`lsof -t -i TCP:${port} -sTCP:LISTEN 2>/dev/null`, { encoding: "utf8" }).trim();
      if (pids) {
        execSync(`kill -9 ${pids.split("\n").join(" ")}`);
        console.log("Bridge killed");
      } else {
        console.log(`No listener on port ${port}`);
      }
    } catch {
      console.log(`No listener on port ${port}`);
    }
  }
}
