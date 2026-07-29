import {
  ForbiddenException,
  NotFoundException,
} from "@nestjs/common";
import { readFileSync } from "fs";
import { resolve } from "path";
import {
  ActorClientProjectionFactory,
  CLIENT_PROJECTION_SURFACES,
  ClientProjectionSource,
} from "./actor-client-projection.factory";
import { USER_ROLES } from "./capability-registry";

const factory = new ActorClientProjectionFactory();

const source: ClientProjectionSource = {
  id: "client-1",
  userId: "client-user-1",
  displayName: "Visible Student",
  lifecycleStatus: "active",
  branchId: "branch-1",
  contacts: {
    phone: "FORBIDDEN_PHONE_VALUE",
    email: "FORBIDDEN_EMAIL_VALUE",
    address: "FORBIDDEN_ADDRESS_VALUE",
  },
  representatives: [
    {
      id: "representative-1",
      name: "FORBIDDEN_REPRESENTATIVE_VALUE",
      phone: "FORBIDDEN_REPRESENTATIVE_PHONE",
      relationship: "parent",
    },
  ],
  lessons: [
    {
      id: "lesson-1",
      scheduledAt: "2026-07-25T10:00:00.000Z",
      status: "scheduled",
      teacherRate: 900,
      clientCost: 1500,
    },
  ],
  homework: [
    {
      id: "homework-1",
      title: "Visible exercise",
      status: "assigned",
    },
  ],
  comments: [
    {
      id: "comment-shared",
      body: "Visible shared note",
      sharedWithTeacher: true,
    },
    {
      id: "comment-private",
      body: "FORBIDDEN_PRIVATE_COMMENT",
      sharedWithTeacher: false,
    },
  ],
  finance: {
    balance: 4000,
    debt: 1200,
    payments: [
      {
        id: "payment-1",
        amount: 5000,
        paidAt: "2026-07-01T10:00:00.000Z",
      },
    ],
  },
  subscriptions: [
    {
      id: "subscription-1",
      packageName: "FORBIDDEN_SUBSCRIPTION_VALUE",
      remainingLessons: 4,
      price: 8000,
    },
  ],
};

const assignedScope = {
  self: false,
  assigned: true,
  branchAllowed: true,
};

const forbiddenTeacherKey =
  /contacts?|representatives?|finance|subscriptions?|payments?|balance|debt|price|cost|rate|phone|email|address/i;
const forbiddenTeacherValue = /FORBIDDEN_/;

function collectKeys(value: unknown): string[] {
  if (Array.isArray(value)) return value.flatMap(collectKeys);
  if (!value || typeof value !== "object") return [];
  return Object.entries(value as Record<string, unknown>).flatMap(
    ([key, child]) => [key, ...collectKeys(child)],
  );
}

describe("ActorClientProjectionFactory Teacher contract", () => {
  it.each(CLIENT_PROJECTION_SURFACES)(
    "removes forbidden keys and values before %s composition",
    (surface) => {
      const projected = factory.project(
        { userId: "teacher-1", role: "teacher" },
        source,
        assignedScope,
        surface,
      );
      expect(projected.projection).toBe("teacher_assigned");
      expect(collectKeys(projected.client)).not.toEqual(
        expect.arrayContaining([
          expect.stringMatching(forbiddenTeacherKey),
        ]),
      );
      expect(JSON.stringify(projected)).not.toMatch(forbiddenTeacherValue);
      expect(projected.client).toMatchObject({
        id: "client-1",
        lessons: [{ id: "lesson-1", status: "scheduled" }],
        homework: [{ id: "homework-1" }],
        sharedComments: [
          { id: "comment-shared", body: "Visible shared note" },
        ],
      });
    },
  );

  it("returns safe 404 for an unrelated Teacher client", () => {
    expect(() =>
      factory.project(
        { userId: "teacher-1", role: "teacher" },
        source,
        { ...assignedScope, assigned: false },
        "client",
      ),
    ).toThrow(NotFoundException);
  });

  it("filters unrelated clients before list/search serialization", () => {
    const projected = factory.projectCollection(
      { userId: "teacher-1", role: "teacher" },
      [
        { source, scope: assignedScope },
        {
          source: { ...source, id: "client-unrelated" },
          scope: { ...assignedScope, assigned: false },
        },
      ],
      "search",
    );
    expect(projected).toHaveLength(1);
    expect(projected[0]?.client.id).toBe("client-1");
  });
});

describe("ActorClientProjectionFactory six-role scopes", () => {
  it.each([
    ["client", "client_self"],
    ["teacher", "teacher_assigned"],
    ["admin", "admin_scoped"],
    ["manager", "manager_scoped"],
    ["director", "director_scoped"],
    ["system_admin", "system_admin_emergency"],
  ] as const)("maps %s to the isolated %s contract", (role, profile) => {
    expect(factory.profileFor(role)).toBe(profile);
  });

  it("allows Client self scope and hides unrelated Client resources", () => {
    expect(
      factory.project(
        { userId: "client-user-1", role: "client" },
        source,
        { self: true, assigned: false, branchAllowed: false },
        "client",
      ).client,
    ).toHaveProperty("account");
    expect(() =>
      factory.project(
        { userId: "other-client", role: "client" },
        source,
        { self: false, assigned: false, branchAllowed: false },
        "client",
      ),
    ).toThrow(NotFoundException);
  });

  it.each(["admin", "manager", "director"] as const)(
    "returns 403 when %s is outside branch scope",
    (role) => {
      expect(() =>
        factory.project(
          { userId: `${role}-1`, role },
          source,
          { self: false, assigned: false, branchAllowed: false },
          "client",
        ),
      ).toThrow(ForbiddenException);
    },
  );

  it("partitions caches by projection, actor, access version, surface and scope", () => {
    const base = {
      actor: { userId: "teacher-1", role: "teacher" as const },
      accessVersion: 4,
      surface: "client" as const,
      scopeKey: "assigned:teacher-1",
    };
    const keys = [
      factory.cachePartitionKey(base),
      factory.cachePartitionKey({
        ...base,
        actor: { userId: "teacher-2", role: "teacher" },
      }),
      factory.cachePartitionKey({ ...base, accessVersion: 5 }),
      factory.cachePartitionKey({ ...base, surface: "search" }),
      factory.cachePartitionKey({
        ...base,
        actor: { userId: "manager-1", role: "manager" },
      }),
    ];
    expect(new Set(keys).size).toBe(keys.length);
  });

  it("declares six separate OpenAPI projection schemas with a safe Teacher shape", () => {
    const contract = JSON.parse(
      readFileSync(
        resolve(
          process.cwd(),
          "..",
          "docs",
          "contracts",
          "v4-client-projections.openapi.json",
        ),
        "utf8",
      ),
    ) as {
      components: {
        schemas: Record<
          string,
          { properties?: Record<string, unknown> }
        >;
      };
    };
    const schemas = contract.components.schemas;
    for (const role of USER_ROLES) {
      expect(schemas[`${role}_client_projection`]).toBeDefined();
    }
    const teacherKeys = collectKeys(
      schemas.teacher_client_projection?.properties ?? {},
    );
    expect(teacherKeys).not.toEqual(
      expect.arrayContaining([expect.stringMatching(forbiddenTeacherKey)]),
    );
  });
});
