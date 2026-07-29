import {
  ForbiddenException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { AccessRole } from "./capability-registry";

export const CLIENT_PROJECTION_SURFACES = [
  "client",
  "search",
  "schedule",
  "chat",
  "finance",
  "export",
] as const;

export type ClientProjectionSurface =
  (typeof CLIENT_PROJECTION_SURFACES)[number];

export type ClientProjectionProfile =
  | "client_self"
  | "teacher_assigned"
  | "admin_scoped"
  | "manager_scoped"
  | "director_scoped"
  | "system_admin_emergency";

export interface ClientProjectionScope {
  self: boolean;
  assigned: boolean;
  branchAllowed: boolean;
}

export interface ClientProjectionSource {
  id: string;
  userId: string | null;
  displayName: string;
  lifecycleStatus: string;
  branchId: string | null;
  contacts: {
    phone: string | null;
    email: string | null;
    address: string | null;
  };
  representatives: Array<{
    id: string;
    name: string;
    phone: string | null;
    relationship: string;
  }>;
  lessons: Array<{
    id: string;
    scheduledAt: string;
    status: string;
    teacherRate: number | null;
    clientCost: number | null;
  }>;
  homework: Array<{
    id: string;
    title: string;
    status: string;
  }>;
  comments: Array<{
    id: string;
    body: string;
    sharedWithTeacher: boolean;
  }>;
  finance: {
    balance: number;
    debt: number;
    payments: Array<{
      id: string;
      amount: number;
      paidAt: string;
    }>;
  };
  subscriptions: Array<{
    id: string;
    packageName: string;
    remainingLessons: number;
    price: number;
  }>;
}

export interface ProjectedClientEnvelope {
  projection: ClientProjectionProfile;
  surface: ClientProjectionSurface;
  client: Record<string, unknown>;
}

const profileByRole: Readonly<Record<AccessRole, ClientProjectionProfile>> = {
  client: "client_self",
  teacher: "teacher_assigned",
  admin: "admin_scoped",
  manager: "manager_scoped",
  director: "director_scoped",
  system_admin: "system_admin_emergency",
};

@Injectable()
export class ActorClientProjectionFactory {
  profileFor(role: AccessRole): ClientProjectionProfile {
    return profileByRole[role];
  }

  project(
    actor: ActorContext,
    source: ClientProjectionSource,
    scope: ClientProjectionScope,
    surface: ClientProjectionSurface,
  ): ProjectedClientEnvelope {
    this.assertScope(actor.role, scope);
    const projection = this.profileFor(actor.role);
    const base = {
      id: source.id,
      displayName: source.displayName,
      lifecycleStatus: source.lifecycleStatus,
    };
    const safeLessons = source.lessons.map((lesson) => ({
      id: lesson.id,
      scheduledAt: lesson.scheduledAt,
      status: lesson.status,
    }));
    const safeHomework = source.homework.map((homework) => ({
      id: homework.id,
      title: homework.title,
      status: homework.status,
    }));

    if (actor.role === "teacher") {
      return {
        projection,
        surface,
        client: {
          ...base,
          lessons: safeLessons,
          homework: safeHomework,
          sharedComments: source.comments
            .filter((comment) => comment.sharedWithTeacher)
            .map((comment) => ({
              id: comment.id,
              body: comment.body,
            })),
        },
      };
    }

    if (actor.role === "client") {
      return {
        projection,
        surface,
        client: {
          ...base,
          lessons: safeLessons,
          homework: safeHomework,
          account: {
            balance: source.finance.balance,
            debt: source.finance.debt,
            payments: source.finance.payments.map((payment) => ({
              id: payment.id,
              amount: payment.amount,
              paidAt: payment.paidAt,
            })),
            subscriptions: source.subscriptions.map((subscription) => ({
              id: subscription.id,
              packageName: subscription.packageName,
              remainingLessons: subscription.remainingLessons,
            })),
          },
        },
      };
    }

    const operational = {
      ...base,
      branchId: source.branchId,
      contacts: { ...source.contacts },
      representatives: source.representatives.map((representative) => ({
        ...representative,
      })),
      lessons: source.lessons.map((lesson) => ({ ...lesson })),
      homework: safeHomework,
      finance: {
        balance: source.finance.balance,
        debt: source.finance.debt,
        payments: source.finance.payments.map((payment) => ({ ...payment })),
      },
      subscriptions: source.subscriptions.map((subscription) => ({
        ...subscription,
      })),
    };

    if (actor.role === "admin" || actor.role === "manager") {
      return { projection, surface, client: operational };
    }

    return {
      projection,
      surface,
      client: {
        ...operational,
        comments: source.comments.map((comment) => ({ ...comment })),
      },
    };
  }

  projectCollection(
    actor: ActorContext,
    sources: ReadonlyArray<{
      source: ClientProjectionSource;
      scope: ClientProjectionScope;
    }>,
    surface: ClientProjectionSurface,
  ): ProjectedClientEnvelope[] {
    return sources.flatMap((candidate) => {
      try {
        return [this.project(actor, candidate.source, candidate.scope, surface)];
      } catch (error) {
        if (
          error instanceof NotFoundException ||
          error instanceof ForbiddenException
        ) {
          return [];
        }
        throw error;
      }
    });
  }

  cachePartitionKey(input: {
    actor: ActorContext;
    accessVersion: number;
    surface: ClientProjectionSurface;
    scopeKey: string;
  }): string {
    if (
      !Number.isSafeInteger(input.accessVersion) ||
      input.accessVersion < 1 ||
      !/^[A-Za-z0-9._:-]{1,160}$/.test(input.scopeKey)
    ) {
      throw new TypeError("Invalid projection cache partition metadata.");
    }
    return [
      "client-projection",
      "v1",
      this.profileFor(input.actor.role),
      input.actor.userId,
      input.accessVersion,
      input.surface,
      input.scopeKey,
    ].join(":");
  }

  private assertScope(role: AccessRole, scope: ClientProjectionScope): void {
    if (role === "system_admin") return;
    if (role === "client" && !scope.self) {
      throw new NotFoundException({
        code: "CLIENT_SCOPE_NOT_FOUND",
        message: "Client resource was not found.",
      });
    }
    if (role === "teacher" && !scope.assigned) {
      throw new NotFoundException({
        code: "TEACHER_ASSIGNMENT_NOT_FOUND",
        message: "Client resource was not found.",
      });
    }
    if (
      role !== "client" &&
      role !== "teacher" &&
      !scope.branchAllowed
    ) {
      throw new ForbiddenException({
        code: "CLIENT_BRANCH_SCOPE_DENIED",
        message: "Client is outside the actor branch scope.",
      });
    }
  }
}
