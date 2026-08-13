import { spawnSync } from "child_process";
import { existsSync, readdirSync, readFileSync, statSync } from "fs";
import { join, relative, resolve } from "path";

type CheckStatus = "pass" | "warn" | "fail";

interface CheckResult {
  name: string;
  status: CheckStatus;
  detail: string;
}

const serverRoot = resolve(__dirname, "..", "..");
const repoRoot = resolve(serverRoot, "..");
const strict = process.env.SECURITY_GATE_STRICT === "1";
const auditLevel = process.env.SECURITY_GATE_AUDIT_LEVEL?.trim() || "moderate";
const results: CheckResult[] = [];

function main() {
  checkGitDiff();
  checkIgnoredArtifactPaths();
  checkDockerIgnore();
  checkPublicEnvFiles();
  checkGeneratedSourceMaps();
  checkFrontendRuntimeSecrets();
  checkNpmAudit();
  checkExternalTool("gitleaks", "history-aware secret scanning");
  checkExternalTool("semgrep", "SAST scanning");
  checkExternalTool("trivy", "dependency/container scanning");
  checkDockerDaemon();

  const summary = results.reduce(
    (acc, result) => {
      acc[result.status] += 1;
      return acc;
    },
    { pass: 0, warn: 0, fail: 0 },
  );

  console.log(JSON.stringify({ strict, summary, results }, null, 2));
  if (summary.fail > 0) process.exit(1);
}

function add(name: string, status: CheckStatus, detail: string) {
  results.push({ name, status, detail });
}

function run(
  command: string,
  args: string[],
  cwd = repoRoot,
): { status: number; stdout: string; stderr: string } {
  const child = spawnSync(resolveCommand(command), args, {
    cwd,
    encoding: "utf8",
    shell: false,
  });
  return {
    status: child.status ?? 1,
    stdout: child.stdout ?? "",
    stderr: child.stderr ?? "",
  };
}

function checkGitDiff() {
  const result = run("git", ["diff", "--check"]);
  const output = `${result.stdout}${result.stderr}`.trim();
  add(
    "git-diff-check",
    result.status === 0 ? "pass" : "fail",
    output || "No whitespace or conflict-marker issues found.",
  );
}

function checkIgnoredArtifactPaths() {
  const paths = [
    "server/exports/security-gate-placeholder.ndjson",
    "server/storage/security-gate-placeholder.bin",
  ];
  const failures = paths.filter(
    (path) => run("git", ["check-ignore", path]).status !== 0,
  );
  add(
    "sensitive-artifact-git-ignore",
    failures.length === 0 ? "pass" : "fail",
    failures.length === 0
      ? "server/exports and server/storage are ignored by Git."
      : `Missing Git ignore coverage: ${failures.join(", ")}`,
  );
}

function checkDockerIgnore() {
  const dockerIgnorePath = join(serverRoot, ".dockerignore");
  const content = existsSync(dockerIgnorePath)
    ? readFileSync(dockerIgnorePath, "utf8")
    : "";
  const required = ["exports/", "storage/", "security-scans/"];
  const missing = required.filter((entry) => !content.includes(entry));
  add(
    "sensitive-artifact-docker-ignore",
    missing.length === 0 ? "pass" : "fail",
    missing.length === 0
      ? "Docker build context excludes exports, storage and security scan artifacts."
      : `Missing .dockerignore entries: ${missing.join(", ")}`,
  );
}

function checkPublicEnvFiles() {
  const envFiles = walk(repoRoot).filter((path) => {
    const name = path.split(/[\\/]/).pop() ?? "";
    if (name === ".env.example") return false;
    return name === ".env" || name.startsWith(".env.");
  });
  const unsafeEnvFiles = envFiles.filter(
    (path) => isGitTracked(path) || !isGitIgnored(path),
  );
  add(
    "public-env-files",
    unsafeEnvFiles.length === 0 ? "pass" : "fail",
    unsafeEnvFiles.length === 0
      ? "No tracked or unignored runtime .env files found in scanned paths."
      : `Tracked or unignored runtime env files present: ${unsafeEnvFiles
          .map(toRepoPath)
          .join(", ")}`,
  );
}

function checkGeneratedSourceMaps() {
  const sourceMaps = walk(repoRoot).filter((path) => path.endsWith(".map"));
  add(
    "production-source-maps",
    sourceMaps.length === 0 ? "pass" : "warn",
    sourceMaps.length === 0
      ? "No source maps found in scanned paths."
      : `Source maps found and must not be published: ${sourceMaps
          .map(toRepoPath)
          .join(", ")}`,
  );
}

function checkFrontendRuntimeSecrets() {
  const envPath = join(repoRoot, "lib", "core", "constants", "env.dart");
  const mainPath = join(repoRoot, "lib", "main.dart");
  const pubspecPath = join(repoRoot, "pubspec.yaml");
  const env = readFileSync(envPath, "utf8");
  const main = readFileSync(mainPath, "utf8");
  const pubspec = readFileSync(pubspecPath, "utf8");
  const failures: string[] = [];

  if (/LEGACY_SUPABASE_(URL|ANON_KEY)/.test(env)) {
    failures.push("Legacy Supabase dart-defines must not be loaded by Flutter runtime");
  }
  if (/HOLLIHOP_AUTH_KEY/.test(env)) {
    failures.push("HOLLIHOP_AUTH_KEY must stay backend-only and must not be loaded by Flutter");
  }
  if (main.includes("Supabase.initialize") || main.includes("supabase_flutter")) {
    failures.push("main.dart still initializes or imports Supabase runtime");
  }
  if (pubspec.includes("supabase_flutter:")) {
    failures.push("pubspec.yaml still depends on supabase_flutter runtime");
  }

  add(
    "frontend-runtime-secret-defaults",
    failures.length === 0 ? "pass" : "fail",
    failures.length === 0
      ? "Flutter uses owned v3 backend runtime; legacy Supabase dart-defines and HolliHop secrets are not loaded by Flutter."
      : failures.join("; "),
  );
}

function checkNpmAudit() {
  const result =
    process.platform === "win32"
      ? run(
          process.env.ComSpec ?? "cmd.exe",
          ["/d", "/s", "/c", "npm", "audit", `--audit-level=${auditLevel}`],
          serverRoot,
        )
      : run("npm", ["audit", `--audit-level=${auditLevel}`], serverRoot);
  const output = `${result.stdout}${result.stderr}`.trim();
  add(
    "npm-audit",
    result.status === 0 ? "pass" : "fail",
    output || `npm audit completed at ${auditLevel} threshold.`,
  );
}

function checkExternalTool(binary: string, purpose: string) {
  const command = process.platform === "win32" ? "where" : "which";
  const args = [binary];
  const result = run(command, args);
  const available = result.status === 0;
  add(
    `${binary}-available`,
    available ? "pass" : strict ? "fail" : "warn",
    available
      ? `${binary} is available for ${purpose}.`
      : `${binary} is not available locally; ${purpose} remains a production gate.`,
  );
}

function checkDockerDaemon() {
  const result = run("docker", ["info"]);
  add(
    "docker-daemon",
    result.status === 0 ? "pass" : strict ? "fail" : "warn",
    result.status === 0
      ? "Docker daemon is reachable for image scanning."
      : "Docker daemon is not reachable; container image scanning remains pending.",
  );
}

function walk(root: string): string[] {
  const ignored = new Set([
    ".dart_tool",
    ".git",
    ".idea",
    ".tmp",
    ".vscode",
    "build",
    "dist",
    "node_modules",
    "exports",
    "storage",
  ]);
  const output: string[] = [];

  for (const entry of readdirSync(root)) {
    if (ignored.has(entry)) continue;
    const fullPath = join(root, entry);
    const stats = statSync(fullPath);
    if (stats.isDirectory()) {
      output.push(...walk(fullPath));
    } else {
      output.push(fullPath);
    }
  }

  return output;
}

function toRepoPath(path: string): string {
  return relative(repoRoot, path).replace(/\\/g, "/");
}

function isGitIgnored(path: string): boolean {
  return run("git", ["check-ignore", toRepoPath(path)]).status === 0;
}

function isGitTracked(path: string): boolean {
  return run("git", ["ls-files", "--error-unmatch", toRepoPath(path)]).status === 0;
}

function resolveCommand(command: string): string {
  return command;
}

main();
