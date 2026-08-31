import { ConflictException, Injectable, NotFoundException } from "@nestjs/common";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { RealtimeBus } from "../realtime/realtime-bus";
import {
  ValidatedCustomFields,
  ValidatedLeadCreate,
} from "./clients/client-write.validator";
import { CrmPolicy } from "./crm.policy";
import { diffEntityFields } from "./crm-mappers";
import { UpdateLeadDto, UpsertLeadDto } from "./dto/upsert-lead.dto";
import { attachStudentToLead } from "./lead-student-link";
import { toLeadDto } from "./lead-model";
import { LeadWriteRepository } from "./lead-write.repository";
import { ensureResponsibleSafe } from "./responsible";

const LEAD_AUDITED_FIELDS = [
  "status_id",
  "first_name",
  "last_name",
  "phone",
  "email",
  "source",
  "notes",
  "assigned_to",
];

@Injectable()
export class LeadCommandService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly policy: CrmPolicy,
    private readonly realtime: RealtimeBus,
    private readonly writes: LeadWriteRepository,
  ) {}

  async create(
    actor: ActorContext,
    dto: UpsertLeadDto,
    validated?: ValidatedLeadCreate,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const { lead, branchId } = await this.writes.create(actor, dto, validated);
    if (!dto.clearAssignedTo && !dto.assignedTo) {
      const claimedVersion = await ensureResponsibleSafe(
        this.database,
        actor,
        "lead",
        lead.id,
      );
      if (claimedVersion !== null) lead.version = claimedVersion;
    }
    await this.audit.record({
      actor,
      action: "crm.lead_created",
      entityType: "lead",
      entityId: lead.id,
    });
    this.realtime.emitCrmChanged({
      entity: "lead",
      action: "created",
      id: lead.id,
      branchId: branchId ?? null,
    });
    return {
      ...toLeadDto(lead),
      ...(validated ? { warnings: validated.warnings } : {}),
    };
  }

  async update(
    actor: ActorContext,
    leadId: string,
    dto: UpdateLeadDto,
    customFields?: ValidatedCustomFields,
  ) {
    this.policy.assertCanWriteCrm(actor);
    const { before, lead, branchId, customFieldChanges } =
      await this.writes.update(actor, leadId, dto, customFields);
    if (!lead) throw new NotFoundException("Лид не найден.");
    if (!dto.clearAssignedTo && !dto.assignedTo) {
      const claimedVersion = await ensureResponsibleSafe(
        this.database,
        actor,
        "lead",
        lead.id,
      );
      if (claimedVersion !== null) lead.version = claimedVersion;
    }
    await this.audit.record({
      actor,
      action: "crm.lead_updated",
      entityType: "lead",
      entityId: lead.id,
      metadata: {
        changes: [
          ...(before
            ? diffEntityFields(
                before as unknown as Record<string, unknown>,
                lead as unknown as Record<string, unknown>,
                LEAD_AUDITED_FIELDS,
              )
            : []),
          ...customFieldChanges,
        ],
      },
    });
    this.realtime.emitCrmChanged({
      entity: "lead",
      action: "updated",
      id: lead.id,
      branchId: branchId ?? before?.branch_id ?? null,
    });
    return {
      ...toLeadDto(lead),
      ...(customFields ? { warnings: customFields.warnings } : {}),
    };
  }

  async linkStudent(actor: ActorContext, leadId: string, studentId: string) {
    this.policy.assertCanWriteCrm(actor);
    await this.assertEntityExists(
      "app.leads",
      leadId,
      "Лид не найден.",
    );
    await this.assertEntityExists(
      "app.students",
      studentId,
      "Ученик не найден.",
    );
    await attachStudentToLead(this.database, studentId, leadId);
    await this.audit.record({
      actor,
      action: "crm.lead_student_linked",
      entityType: "lead",
      entityId: leadId,
      metadata: { studentId },
    });
    this.realtime.emitCrmChanged({
      entity: "lead",
      action: "updated",
      id: leadId,
    });
    return { leadId, studentId };
  }

  delete(actor: ActorContext, leadId: string) {
    this.policy.assertCanWriteCrm(actor);
    void leadId;
    throw new ConflictException(
      "Прямое удаление лида отключено. Используйте управляемое архивирование с предварительной проверкой связанных данных.",
    );
  }

  private async assertEntityExists(
    table: "app.leads" | "app.students",
    id: string,
    message: string,
  ) {
    const result = await this.database.query<{ id: string }>(
      `select id from ${table} where id = $1 and deleted_at is null limit 1`,
      [id],
    );
    if (!result.rows[0]) throw new NotFoundException(message);
  }
}
