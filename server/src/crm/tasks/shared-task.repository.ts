import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";
import {
  SharedTaskMigrationEvidenceRow,
  SharedTaskRow,
  TaskAudienceRow,
} from "./shared-task.types";

@Injectable()
export class SharedTaskRepository {
  constructor(private readonly database: DatabaseService) {}

  migrationEvidence(
    legacyTaskIds: readonly string[],
  ): Promise<{ rows: SharedTaskMigrationEvidenceRow[] }> {
    return this.database.query<SharedTaskMigrationEvidenceRow>(
      `
        select
          legacy_task_id,
          shared_task_id,
          merge_proof,
          source_fingerprint
        from app.shared_task_legacy_links
        where legacy_task_id = any($1::uuid[])
        order by legacy_task_id
      `,
      [legacyTaskIds],
    );
  }

  lock(client: PoolClient, taskId: string) {
    return client.query<SharedTaskRow>(
      `
        select *
        from app.shared_tasks
        where id = $1 and deleted_at is null
        for update
      `,
      [taskId],
    );
  }

  audiences(client: PoolClient, taskId: string) {
    return client.query<TaskAudienceRow>(
      `
        select *
        from app.task_audiences
        where task_id = $1
        order by audience_type, target_id nulls first, id
      `,
      [taskId],
    );
  }
}
