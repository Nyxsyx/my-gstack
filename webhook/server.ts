/**
 * server.ts — GitHub webhook receiver
 *
 * Listens for GitHub events, verifies the HMAC-SHA256 signature,
 * maps events to gstack skill prompts, and injects them into the
 * Claude Code tmux session via inject-task.sh.
 *
 * Start: bun run webhook/server.ts
 * Or via: webhook/start.sh
 *
 * Required env vars (set in ~/.gstack/env):
 *   GITHUB_WEBHOOK_SECRET   — the secret set in GitHub repo webhook settings
 *   WEBHOOK_PORT            — port to listen on (default: 9000)
 */

import { $ } from "bun";
import { resolve, dirname } from "path";
import { fileURLToPath } from "url";
import {
  handlePullRequest,
  handlePullRequestReview,
  handleWorkflowRun,
  handleIssues,
  handlePush,
} from "./handlers";

const REPO_ROOT = resolve(dirname(fileURLToPath(import.meta.url)), "..");
const INJECT_SCRIPT = resolve(REPO_ROOT, "scripts/inject-task.sh");
const PORT = parseInt(process.env.WEBHOOK_PORT ?? "9000", 10);
const SECRET = process.env.GITHUB_WEBHOOK_SECRET ?? "";

if (!SECRET) {
  console.warn(
    "⚠️  GITHUB_WEBHOOK_SECRET not set — signature verification disabled. Set it in ~/.gstack/env."
  );
}

// --- Signature verification ---

async function verifySignature(body: string, signatureHeader: string | null): Promise<boolean> {
  if (!SECRET) return true; // Skip if no secret configured
  if (!signatureHeader?.startsWith("sha256=")) return false;

  const expected = signatureHeader.slice("sha256=".length);
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(SECRET),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );
  const signature = await crypto.subtle.sign("HMAC", key, new TextEncoder().encode(body));
  const actual = Buffer.from(signature).toString("hex");

  // Constant-time comparison
  if (actual.length !== expected.length) return false;
  let diff = 0;
  for (let i = 0; i < actual.length; i++) {
    diff |= actual.charCodeAt(i) ^ expected.charCodeAt(i);
  }
  return diff === 0;
}

// --- Inject task into tmux session ---

async function injectTask(prompt: string, eventType: string): Promise<void> {
  console.log(`[${new Date().toISOString()}] Injecting task for event: ${eventType}`);
  console.log(`Prompt preview: ${prompt.slice(0, 120).replace(/\n/g, " ")}...`);

  try {
    await $`bash ${INJECT_SCRIPT} ${prompt}`.quiet();
    console.log(`✓ Task injected successfully.`);
  } catch (err) {
    console.error(`✗ Failed to inject task:`, err);
  }
}

// --- Request handler ---

async function handleRequest(req: Request): Promise<Response> {
  if (req.method !== "POST") {
    return new Response("Method not allowed", { status: 405 });
  }

  // Health check
  if (new URL(req.url).pathname === "/health") {
    return new Response(JSON.stringify({ status: "ok", uptime: process.uptime() }), {
      headers: { "Content-Type": "application/json" },
    });
  }

  const body = await req.text();
  const signature = req.headers.get("x-hub-signature-256");
  const eventType = req.headers.get("x-github-event");

  // Verify signature
  if (!(await verifySignature(body, signature))) {
    console.warn(`[${new Date().toISOString()}] ⚠️  Invalid signature — request rejected.`);
    return new Response("Unauthorized", { status: 401 });
  }

  if (!eventType) {
    return new Response("Missing X-GitHub-Event header", { status: 400 });
  }

  let payload: unknown;
  try {
    payload = JSON.parse(body);
  } catch {
    return new Response("Invalid JSON", { status: 400 });
  }

  console.log(`[${new Date().toISOString()}] Received event: ${eventType}`);

  // Map event to prompt
  let prompt: string | null = null;

  switch (eventType) {
    case "pull_request":
      prompt = handlePullRequest(payload as Parameters<typeof handlePullRequest>[0]);
      break;
    case "pull_request_review":
      prompt = handlePullRequestReview(payload as Parameters<typeof handlePullRequestReview>[0]);
      break;
    case "workflow_run":
      prompt = handleWorkflowRun(payload as Parameters<typeof handleWorkflowRun>[0]);
      break;
    case "issues":
      prompt = handleIssues(payload as Parameters<typeof handleIssues>[0]);
      break;
    case "push":
      prompt = handlePush(payload as Parameters<typeof handlePush>[0]);
      break;
    default:
      console.log(`  → No handler for event type: ${eventType} — ignoring.`);
      return new Response("Event ignored", { status: 200 });
  }

  if (!prompt) {
    console.log(`  → Event action not mapped — ignoring.`);
    return new Response("Event action ignored", { status: 200 });
  }

  // Fire and forget — don't block the HTTP response on tmux injection
  injectTask(prompt, eventType);

  return new Response("OK", { status: 200 });
}

// --- Start server ---

const server = Bun.serve({
  port: PORT,
  fetch: handleRequest,
});

console.log(`GitHub webhook receiver listening on port ${PORT}`);
console.log(`Health check: http://localhost:${PORT}/health`);
console.log(`Signature verification: ${SECRET ? "enabled" : "DISABLED (no secret set)"}`);
