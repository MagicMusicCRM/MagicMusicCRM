import { ForbiddenException } from "@nestjs/common";
import { DatabaseService } from "../db/database.service";
import { PoolClient, QueryResult, QueryResultRow } from "pg";
import {
  ActorContext,
} from "../common/security/actor-context";
import {
  AccessRole,
  CAPABILITY_DEFINITIONS,
  CapabilityKey,
  CapabilityEffect,
  CapabilityOverrideMode,
} from "./capability-registry";
import { EffectiveAccessEvaluator } from "./effective-access-evaluator";
import {
  CapabilityRoutePolicy,
  resolveCapabilityRoutePolicy,
} from "./capability-route-policy";

interface ActorCapabilityRow {
  role: AccessRole;
  active: boolean;
  definition_active: boolean;
  definition_override_mode: CapabilityOverrideMode | null;
  role_effect: CapabilityEffect | null;
  override_effect: CapabilityEffect | null;
}

const definitionsByKey = new Map(
  CAPABILITY_DEFINITIONS.map((definition) => [definition.key, definition]),
);

type CapabilityQueryable = Pick<PoolClient, "query"> | DatabaseService;

function runQuery<T extends QueryResultRow>(
  queryable: CapabilityQueryable,
  text: string,
  params: unknown[],
): Promise<QueryResult<T>> {
  return (
    queryable.query as (
      query: string,
      values?: unknown[],
    ) => Promise<QueryResult<T>>
  )(text, params);
}

export interface CapabilityAuthorizationResult {
  policy: CapabilityRoutePolicy;
  source: string;
  reason: string;
}

export async function authorizeCurrentCapability(
  queryable: CapabilityQueryable,
  tokenActor: ActorContext,
  capabilityKey: CapabilityKey,
  lockForCommit = false,
): Promise<{ source: string; reason: string }> {
  const definition = definitionsByKey.get(capabilityKey);
  if (!definition) {
    throw new ForbiddenException({
      code: "UNKNOWN_ROUTE_CAPABILITY",
      message: "Route capability is not registered.",
    });
  }
  if (lockForCommit) {
    await runQuery(
      queryable,
      `select id from app.users where id = $1 for share`,
      [tokenActor.userId],
    );
    await runQuery(
      queryable,
      `select package.id
         from app.role_packages package
         join app.users user_account on user_account.role = package.role
        where user_account.id = $1 and package.active
        for share of package`,
      [tokenActor.userId],
    );
  }
  const result = await runQuery<ActorCapabilityRow>(
    queryable,
    `
      select
        user_account.role,
        (user_account.deleted_at is null and user_account.is_app_account = true)
          as active,
        coalesce(definition.active, false) as definition_active,
        definition.override_mode as definition_override_mode,
        package_entry.effect as role_effect,
        personal_override.effect as override_effect
      from app.users user_account
      left join app.capability_definitions definition
        on definition.capability_key = $2
       and definition.version = $3
      left join app.role_packages package
        on package.role = user_account.role
       and package.active = true
      left join app.role_package_capabilities package_entry
        on package_entry.package_id = package.id
       and package_entry.capability_key = definition.capability_key
       and package_entry.capability_version = definition.version
      left join app.user_capability_overrides personal_override
        on personal_override.user_id = user_account.id
       and personal_override.capability_key = definition.capability_key
       and personal_override.capability_version = definition.version
       and personal_override.active = true
      where user_account.id = $1
      limit 1
    `,
    [tokenActor.userId, capabilityKey, definition.version],
  );
  const row = result.rows[0];
  const decision = new EffectiveAccessEvaluator().evaluate({
    actor: {
      userId: tokenActor.userId,
      role: row?.role ?? tokenActor.role,
      active: row?.active === true,
    },
    capability: {
      key: capabilityKey,
      active: row?.definition_active === true,
      overrideMode: row?.definition_override_mode ?? definition.overrideMode,
    },
    roleEffect: row?.role_effect,
    overrideEffect: row?.override_effect,
    resourceAllowed: true,
  });
  if (!decision.allowed) {
    throw new ForbiddenException({
      code: "CAPABILITY_DENIED",
      capabilityKey,
      source: decision.source,
      reason: decision.reason,
    });
  }
  return { source: decision.source, reason: decision.reason };
}

export class CapabilityRequestAuthorizer {
  constructor(private readonly database: DatabaseService) {}

  async authorize(
    tokenActor: ActorContext,
    method: string,
    path: string,
  ): Promise<CapabilityAuthorizationResult> {
    const routePolicy = resolveCapabilityRoutePolicy(method, path);
    if (routePolicy.authenticatedOnly) {
      return {
        policy: routePolicy,
        source: "actor",
        reason: "authenticated_self_snapshot",
      };
    }
    const decision = await authorizeCurrentCapability(
      this.database,
      tokenActor,
      routePolicy.capabilityKey,
    );
    return {
      policy: routePolicy,
      ...decision,
    };
  }
}
