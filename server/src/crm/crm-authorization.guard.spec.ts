import * as fs from "node:fs";
import * as path from "node:path";

/**
 * Structural authorization guard (architecture audit, priority #3).
 *
 * Two authorization models coexist in the CRM: declarative (@Roles + RolesGuard
 * on controllers) and imperative (CrmPolicy.assert* / role helpers inside
 * services). The imperative one is easy to forget — nothing structurally
 * guarantees that a new actor-taking service method authorizes the caller.
 *
 * This test closes that gap: every public/private method whose first parameter
 * is `actor: ActorContext` MUST carry a recognized authorization marker, OR be
 * listed in ALLOWLIST with an explicit reason. Adding a new CRM method that
 * takes an actor but neither authorizes nor documents why fails this test.
 *
 * It is intentionally a source-text heuristic (no runtime wiring), so it stays
 * cheap and catches the "someone forgot to think about auth" case without
 * mandating a single mechanism.
 */

const CRM_DIR = path.join(__dirname);

// Recognized authorization markers inside a method body.
const AUTH_MARKERS: RegExp[] = [
  /this\.policy\./, // CrmPolicy.assert*/can*
  /\bassert[A-Z]\w*\(/, // any assertCanXxx(...)
  /canAssignRole\(/,
  /\bisAdminRole\(/,
  /\bisManagerOrAdminRole\(/,
  /\bisSystemAdminRole\(/,
  /actor\.userId/, // ownership / self-scope reads
  /actor\.role/, // explicit role/hierarchy authorization helper
  /\$1::text in \(/, // row-level role SQL predicate (e.g. listLessons)
  /role(Filter|Clause|Predicate|Scope)/i,
];

// A method that hands the actor to another method delegates authorization.
const DELEGATION = /\b\w+\(\s*actor\b/;

/**
 * Methods intentionally exempt from carrying an auth marker, each with a reason.
 * Keyed by "<file> :: <method>". Keep this list SHORT and justified — every
 * entry is a place the structural guarantee is waived on purpose.
 */
const ALLOWLIST: Record<string, string> = {
  "lead-intake.service.ts :: autoCreateLeadFromChat":
    "Inbound capture invoked via LEAD_INTAKE_PORT when a client sends their " +
    "first chat message; the actor is that client and the flow creates a lead " +
    "from their own message — there is no CRM-management action to authorize.",
  "lead-intake.service.ts :: saveContactFromChat":
    "Inbound capture (chat → lead/student) via LEAD_INTAKE_PORT; same rationale " +
    "as autoCreateLeadFromChat.",
};

interface Method {
  name: string;
  body: string;
}

/** Extract every `name(actor: ActorContext, …)` method with its body,
 *  correctly skipping inline object types in the param list and return type. */
function extractActorMethods(src: string): Method[] {
  const out: Method[] = [];
  const re =
    /(?:^|\n)[ \t]*(?:private\s+|protected\s+|public\s+)?(?:async\s+)?([a-zA-Z_]\w*)\s*\(\s*actor:\s*ActorContext/g;
  let m: RegExpExecArray | null;
  while ((m = re.exec(src))) {
    const name = m[1];
    if (name === "constructor") continue;
    // Opening paren of the param list (the "(" just before "actor").
    const paren = src.lastIndexOf("(", re.lastIndex);
    // Paren-match to the closing ")".
    let pd = 0;
    let k = paren;
    for (; k < src.length; k++) {
      const c = src[k];
      if (c === "(") pd++;
      else if (c === ")") {
        pd--;
        if (pd === 0) {
          k++;
          break;
        }
      }
    }
    // Body "{" = first "{" after the param list at angle-bracket depth 0, so an
    // inline object return type like Promise<{ count: number }> is skipped.
    let angle = 0;
    let brace = -1;
    for (let i = k; i < src.length; i++) {
      const c = src[i];
      if (c === "<") angle++;
      else if (c === ">") angle = Math.max(0, angle - 1);
      else if (c === "{" && angle === 0) {
        brace = i;
        break;
      }
    }
    if (brace < 0) continue;
    let bd = 0;
    let j = brace;
    for (; j < src.length; j++) {
      const c = src[j];
      if (c === "{") bd++;
      else if (c === "}") {
        bd--;
        if (bd === 0) {
          j++;
          break;
        }
      }
    }
    out.push({ name, body: src.slice(brace, j) });
  }
  return out;
}

function serviceFiles(): string[] {
  return fs
    .readdirSync(CRM_DIR)
    .filter((f) => f.endsWith(".service.ts") && !f.endsWith(".spec.ts"))
    .sort();
}

describe("CRM authorization structural guard", () => {
  it("every actor-taking CRM service method authorizes or is allowlisted", () => {
    const offenders: string[] = [];
    let scanned = 0;

    for (const file of serviceFiles()) {
      const src = fs.readFileSync(path.join(CRM_DIR, file), "utf8");
      for (const method of extractActorMethods(src)) {
        scanned++;
        const key = `${file} :: ${method.name}`;
        if (key in ALLOWLIST) continue;
        const authorized =
          AUTH_MARKERS.some((r) => r.test(method.body)) ||
          DELEGATION.test(method.body);
        if (!authorized) offenders.push(key);
      }
    }

    // Sanity: the scanner must actually find the CRM surface, else a regex
    // regression would make this test vacuously pass.
    expect(scanned).toBeGreaterThan(80);

    expect(offenders).toEqual([]);
  });

  it("does not carry stale allowlist entries", () => {
    // Every allowlisted method must still exist; a removed method should be
    // pruned from ALLOWLIST rather than lingering as dead config.
    const present = new Set<string>();
    for (const file of serviceFiles()) {
      const src = fs.readFileSync(path.join(CRM_DIR, file), "utf8");
      for (const method of extractActorMethods(src)) {
        present.add(`${file} :: ${method.name}`);
      }
    }
    const stale = Object.keys(ALLOWLIST).filter((k) => !present.has(k));
    expect(stale).toEqual([]);
  });
});
