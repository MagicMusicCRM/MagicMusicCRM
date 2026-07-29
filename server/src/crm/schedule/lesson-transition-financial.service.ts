import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";

@Injectable()
export class LessonTransitionFinancialService {
  async apply(
    client: PoolClient,
    input: {
      lessonId: string;
      decision: {
        chargeClient: boolean;
        compensateTeacher: boolean;
      };
    },
  ): Promise<void> {
    // T5.3.2 replaces this boundary with financial fact creation. Until then,
    // a terminal source cannot retain a future reservation; the immutable
    // transition keeps the operator decision for that commerce command.
    await client.query(
      `
        update app.lesson_reservations
        set state = 'released'
        where lesson_id = $1 and state = 'reserved'
      `,
      [input.lessonId],
    );
  }
}
