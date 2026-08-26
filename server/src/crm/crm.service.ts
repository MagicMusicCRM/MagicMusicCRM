import { Injectable } from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import type {
  ValidatedCustomFields,
  ValidatedStudentCreate,
} from "./clients/client-write.validator";
import { CrmListQuery } from "./dto/crm-list.query";
import { CreateStudentDto } from "./dto/create-student.dto";
import { StudentSearchQuery } from "./dto/student-search.query";
import { UpdateStudentDto } from "./dto/update-student.dto";
import { StudentCardTimelineService } from "./students/student-card-timeline.service";
import { StudentCommandService } from "./students/student-command.service";
import { StudentDirectoryService } from "./students/student-directory.service";
import { StudentSelfSummaryService } from "./students/student-self-summary.service";

@Injectable()
export class CrmService {
  constructor(
    private readonly directory: StudentDirectoryService,
    private readonly summary: StudentSelfSummaryService,
    private readonly cardTimeline: StudentCardTimelineService,
    private readonly commands: StudentCommandService,
  ) {}

  getMySummary(actor: ActorContext) {
    return this.summary.getMySummary(actor);
  }

  listStudents(actor: ActorContext, query: CrmListQuery) {
    return this.directory.listStudents(actor, query);
  }

  searchStudents(actor: ActorContext, query: StudentSearchQuery) {
    return this.directory.searchStudents(actor, query);
  }

  createStudent(
    actor: ActorContext,
    dto: CreateStudentDto,
    validated?: ValidatedStudentCreate,
  ) {
    return this.commands.createStudent(actor, dto, validated);
  }

  getStudent(actor: ActorContext, studentId: string) {
    return this.directory.getStudent(actor, studentId);
  }

  getStudentCard(actor: ActorContext, studentId: string) {
    return this.cardTimeline.getStudentCard(actor, studentId);
  }

  listStudentGroups(
    actor: ActorContext,
    studentId: string,
    query: CrmListQuery,
  ) {
    return this.directory.listStudentGroups(actor, studentId, query);
  }

  updateStudent(
    actor: ActorContext,
    studentId: string,
    dto: UpdateStudentDto,
    customFields?: ValidatedCustomFields,
  ) {
    return this.commands.updateStudent(actor, studentId, dto, customFields);
  }

  inviteStudent(actor: ActorContext, studentId: string) {
    return this.commands.inviteStudent(actor, studentId);
  }

  listGroupStudents(
    actor: ActorContext,
    groupId: string,
    query: CrmListQuery,
  ) {
    return this.directory.listGroupStudents(actor, groupId, query);
  }

  deleteStudent(actor: ActorContext, studentId: string) {
    return this.commands.deleteStudent(actor, studentId);
  }

  returnStudentToLead(actor: ActorContext, studentId: string) {
    return this.commands.returnStudentToLead(actor, studentId);
  }
}
