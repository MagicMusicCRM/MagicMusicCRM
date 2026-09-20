import { NotFoundException, UnprocessableEntityException } from "@nestjs/common";
import type { PoolClient } from "pg";
import { LessonActionableChainService } from "./lesson-actionable-chain.service";
import type {
  LessonActionableChainRow,
  LessonLifecycleRepository,
} from "./lesson-lifecycle.repository";

const actor = {
  userId: "00000000-0000-4000-8000-000000000010",
  role: "manager" as const,
};

const validRow = (
  chainIds: string[],
  overrides: Partial<LessonActionableChainRow> = {},
): LessonActionableChainRow => ({
  chain_ids: chainIds,
  invalid: false,
  scope_violation: false,
  ...overrides,
});

describe("LessonActionableChainService", () => {
  const resolveActionableChain = jest.fn();
  const repository = {
    resolveActionableChain,
  } as unknown as LessonLifecycleRepository;
  const service = new LessonActionableChainService(repository);

  beforeEach(() => resolveActionableChain.mockReset());

  it.each(["lesson-a", "lesson-b", "lesson-c"])(
    "resolves %s to lesson-c with the complete ordered chain",
    async (openedLessonId) => {
      resolveActionableChain.mockResolvedValue(
        validRow(["lesson-a", "lesson-b", "lesson-c"]),
      );

      await expect(service.resolve(actor, openedLessonId)).resolves.toEqual({
        requestedLessonId: openedLessonId,
        actionableLessonId: "lesson-c",
        chainIds: ["lesson-a", "lesson-b", "lesson-c"],
        redirected: openedLessonId !== "lesson-c",
      });
    },
  );

  it.each(["cycle", "fork", "overlong", "broken-backlink", "deleted-successor"])(
    "rejects an invalid %s chain with the stable typed error",
    async () => {
      resolveActionableChain.mockResolvedValue(
        validRow(["lesson-a"], { invalid: true }),
      );

      const promise = service.resolve(actor, "lesson-a");
      await expect(promise).rejects.toBeInstanceOf(UnprocessableEntityException);
      await expect(promise).rejects.toMatchObject({
        status: 422,
        response: { code: "LESSON_RESCHEDULE_CHAIN_INVALID" },
      });
    },
  );

  it("denies a requested lesson outside the actor resource scope", async () => {
    resolveActionableChain.mockResolvedValue(null);

    await expect(service.resolve(actor, "foreign-lesson"))
      .rejects.toBeInstanceOf(NotFoundException);
  });

  it("denies a successor that leaves the actor resource scope", async () => {
    resolveActionableChain.mockResolvedValue(
      validRow(["lesson-a"], { scope_violation: true }),
    );

    await expect(service.resolve(actor, "lesson-a"))
      .rejects.toBeInstanceOf(NotFoundException);
  });

  it("keeps a terminal lesson without a successor as the current node", async () => {
    resolveActionableChain.mockResolvedValue(validRow(["lesson-terminal"]));

    await expect(service.resolve(actor, "lesson-terminal")).resolves.toEqual({
      requestedLessonId: "lesson-terminal",
      actionableLessonId: "lesson-terminal",
      chainIds: ["lesson-terminal"],
      redirected: false,
    });
  });

  it("uses the caller transaction client for the single chain query", async () => {
    const client = {} as PoolClient;
    resolveActionableChain.mockResolvedValue(validRow(["lesson-a"]));

    await service.resolve(actor, "lesson-a", client);

    expect(resolveActionableChain).toHaveBeenCalledWith(actor, "lesson-a", client);
  });
});
