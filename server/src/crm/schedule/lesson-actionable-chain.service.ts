import {
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import type { PoolClient } from "pg";
import type { ActorContext } from "../../common/security/actor-context";
import { LessonLifecycleRepository } from "./lesson-lifecycle.repository";

export interface LessonActionableResolution {
  requestedLessonId: string;
  actionableLessonId: string;
  chainIds: string[];
  redirected: boolean;
}

@Injectable()
export class LessonActionableChainService {
  constructor(private readonly lifecycle: LessonLifecycleRepository) {}

  async resolve(
    actor: ActorContext,
    lessonId: string,
    client?: PoolClient,
  ): Promise<LessonActionableResolution> {
    const row = await this.lifecycle.resolveActionableChain(
      actor,
      lessonId,
      client,
    );
    if (!row || row.scope_violation) {
      throw new NotFoundException({
        code: "LESSON_NOT_FOUND",
        message: "Урок не найден.",
      });
    }
    if (row.invalid || row.chain_ids.length === 0) {
      throw new UnprocessableEntityException({
        code: "LESSON_RESCHEDULE_CHAIN_INVALID",
        message: "Lesson reschedule chain is invalid.",
      });
    }
    const actionableLessonId = row.chain_ids[row.chain_ids.length - 1]!;
    return {
      requestedLessonId: lessonId,
      actionableLessonId,
      chainIds: row.chain_ids,
      redirected: actionableLessonId !== lessonId,
    };
  }
}
