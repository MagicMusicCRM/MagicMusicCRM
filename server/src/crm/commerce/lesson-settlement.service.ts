import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import {
  LessonSettlementPort,
  LessonSettlementResult,
} from "./lesson-settlement.port";
import { LessonSettlementRepository } from "./lesson-settlement.repository";

@Injectable()
export class LessonSettlementService implements LessonSettlementPort {
  constructor(
    private readonly database: DatabaseService,
    private readonly repository: LessonSettlementRepository,
  ) {}

  settle(
    client: PoolClient,
    lessonId: string,
  ): Promise<LessonSettlementResult> {
    return this.repository.settle(client, lessonId);
  }

  settleStandalone(lessonId: string): Promise<LessonSettlementResult> {
    return this.database.transaction((client) => this.settle(client, lessonId));
  }
}
