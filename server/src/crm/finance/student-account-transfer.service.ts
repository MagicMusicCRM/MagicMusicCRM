import {
  BadRequestException,
  Injectable,
  NotFoundException,
} from "@nestjs/common";
import { AuditService } from "../../audit/audit.service";
import { ActorContext } from "../../common/security/actor-context";
import { DatabaseService } from "../../db/database.service";
import { CrmPolicy } from "../crm.policy";
import { CreateTransferDto } from "../dto/create-transfer.dto";
import { findStudent } from "../student-read";

@Injectable()
export class StudentAccountTransferService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
  ) {}

  async createAccountTransfer(
    actor: ActorContext,
    fromStudentId: string,
    dto: CreateTransferDto,
  ) {
    this.policy.assertManagerOnly(actor);
    if (fromStudentId === dto.toStudentId) {
      throw new BadRequestException("Нельзя перевести деньги самому себе.");
    }
    const from = await findStudent(this.database, fromStudentId);
    if (!from) throw new NotFoundException("Ученик-отправитель не найден.");
    const to = await findStudent(this.database, dto.toStudentId);
    if (!to) throw new NotFoundException("Ученик-получатель не найден.");

    const amount = Math.abs(dto.amount);
    const ids = await this.database.transaction(async (client) => {
      const insertLeg = async (
        studentId: string,
        counterpartyId: string,
        kind: "transfer_in" | "transfer_out",
        signedAmount: number,
      ) => {
        const result = await client.query<{ id: string }>(
          `
            insert into app.account_adjustments
              (student_id, branch_id, kind, amount, description,
               counterparty_student_id, occurred_at, created_by)
            values ($1, (select branch_id from app.students where id = $1), $2,
              $3, $4, $5, coalesce($6::timestamptz, now()), $7)
            returning id
          `,
          [
            studentId,
            kind,
            signedAmount,
            dto.description ?? null,
            counterpartyId,
            dto.occurredAt ?? null,
            actor.userId,
          ],
        );
        return result.rows[0].id;
      };
      const outId = await insertLeg(
        fromStudentId,
        dto.toStudentId,
        "transfer_out",
        -amount,
      );
      const inId = await insertLeg(
        dto.toStudentId,
        fromStudentId,
        "transfer_in",
        amount,
      );
      return { outId, inId };
    });

    await this.audit.record({
      actor,
      action: "crm.account_transfer_created",
      entityType: "student",
      entityId: fromStudentId,
      metadata: { toStudentId: dto.toStudentId, amount },
    });
    return { fromAdjustmentId: ids.outId, toAdjustmentId: ids.inId, amount };
  }
}
