import { Injectable, ServiceUnavailableException } from "@nestjs/common";

const V4_DOMAINS = ["access", "schedule"] as const;

export type V4Domain = (typeof V4_DOMAINS)[number];
export type V4CompatibilityMode = "legacy" | "shadow" | "v4";

export interface V4DomainRollout {
  domain: V4Domain;
  configuredMode: V4CompatibilityMode;
  effectivePath: "legacy" | "v4";
  shadowCompare: boolean;
  killSwitch: boolean;
  enableAllowed: boolean;
  reason: string;
}

function modeVariable(domain: V4Domain): string {
  return `V4_${domain.toUpperCase()}_MODE`;
}

function killVariable(domain: V4Domain): string {
  return `V4_${domain.toUpperCase()}_KILL_SWITCH`;
}

export function resolveV4DomainRollout(
  domain: V4Domain,
  environment: NodeJS.ProcessEnv,
  unexplainedParityDiffs: number,
): V4DomainRollout {
  const rawMode = environment[modeVariable(domain)]?.trim().toLowerCase()
    ?? "shadow";
  if (!(["legacy", "shadow", "v4"] as const).includes(
    rawMode as V4CompatibilityMode,
  )) {
    throw new Error(`${modeVariable(domain)} must be legacy, shadow or v4.`);
  }
  const configuredMode = rawMode as V4CompatibilityMode;
  const killSwitch = environment[killVariable(domain)] === "true";
  if (
    environment.NODE_ENV === "production" &&
    (configuredMode !== "v4" || killSwitch || unexplainedParityDiffs !== 0)
  ) {
    throw new Error(
      `${domain} must use verified v4 execution in production.`,
    );
  }
  if (killSwitch) {
    return {
      domain,
      configuredMode,
      effectivePath: "legacy",
      shadowCompare: false,
      killSwitch: true,
      enableAllowed: false,
      reason: "kill_switch",
    };
  }
  if (configuredMode === "v4" && unexplainedParityDiffs > 0) {
    return {
      domain,
      configuredMode,
      effectivePath: "legacy",
      shadowCompare: true,
      killSwitch: false,
      enableAllowed: false,
      reason: "unexplained_parity_diff",
    };
  }
  return {
    domain,
    configuredMode,
    effectivePath: configuredMode === "v4" ? "v4" : "legacy",
    shadowCompare: configuredMode === "shadow",
    killSwitch: false,
    enableAllowed: unexplainedParityDiffs === 0,
    reason: configuredMode === "shadow" ? "shadow_compare" : configuredMode,
  };
}

@Injectable()
export class V4DomainFlagsService {
  get(domain: V4Domain): V4DomainRollout {
    const rawDiffs = process.env.V4_PARITY_UNEXPLAINED_DIFFS ?? "1";
    const unexplainedDiffs = Number(rawDiffs);
    if (!Number.isInteger(unexplainedDiffs) || unexplainedDiffs < 0) {
      throw new Error(
        "V4_PARITY_UNEXPLAINED_DIFFS must be a non-negative integer.",
      );
    }
    return resolveV4DomainRollout(domain, process.env, unexplainedDiffs);
  }

  assertEnabled(domain: V4Domain): V4DomainRollout {
    const rollout = this.get(domain);
    if (rollout.effectivePath !== "v4") {
      throw new ServiceUnavailableException({
        code: "V4_DOMAIN_DISABLED",
        domain,
        reason: rollout.reason,
      });
    }
    return rollout;
  }

  snapshot(): V4DomainRollout[] {
    return V4_DOMAINS.map((domain) => this.get(domain));
  }
}
