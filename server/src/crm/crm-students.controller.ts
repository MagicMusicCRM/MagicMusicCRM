import {
  BadRequestException,
  Body,
  Controller,
  Delete,
  Get,
  Param,
  ParseUUIDPipe,
  Patch,
  Post,
  Query,
  UseGuards,
} from "@nestjs/common";
import { ActorContext } from "../common/security/actor-context";
import { CurrentActor } from "../common/security/current-actor.decorator";
import { JwtAuthGuard } from "../common/security/jwt-auth.guard";
import { BlacklistService } from "./blacklist.service";
import { CrmService } from "./crm.service";
import { SubscriptionsService } from "./subscriptions.service";
import { FinanceService } from "./finance.service";
import { SetBlacklistDto } from "./dto/set-blacklist.dto";
import {
  CreateAdjustmentDto,
  UpdateAdjustmentDto,
} from "./dto/create-adjustment.dto";
import { CreateTransferDto } from "./dto/create-transfer.dto";
import { IssueSubscriptionDto } from "./dto/issue-subscription.dto";
import { CreateStudentDto } from "./dto/create-student.dto";
import { CrmListQuery } from "./dto/crm-list.query";
import { StudentBalanceQuery } from "./dto/student-balance.query";
import { StudentLedgerQuery } from "./dto/student-ledger.query";
import { StudentSearchQuery } from "./dto/student-search.query";
import { UpdateStudentDto } from "./dto/update-student.dto";

@UseGuards(JwtAuthGuard)
@Controller("crm")
export class CrmStudentsController {
  constructor(
    private readonly crm: CrmService,
    private readonly finance: FinanceService,
    private readonly subscriptions: SubscriptionsService,
    private readonly blacklist: BlacklistService,
  ) {}

  @Get("me")
  getMe(@CurrentActor() actor: ActorContext) {
    return this.crm.getMySummary(actor);
  }

  @Get("students")
  listStudents(
    @CurrentActor() actor: ActorContext,
    @Query() query: CrmListQuery,
  ) {
    return this.crm.listStudents(actor, query);
  }

  @Get("students/search")
  searchStudents(
    @CurrentActor() actor: ActorContext,
    @Query() query: StudentSearchQuery,
  ) {
    return this.crm.searchStudents(actor, query);
  }

  @Post("students")
  createStudent(
    @CurrentActor() actor: ActorContext,
    @Body() dto: CreateStudentDto,
  ) {
    if (dto.leadId) {
      throw new BadRequestException(
        "Лид становится учеником только при выдаче абонемента через /crm/leads/:leadId/subscriptions/issue.",
      );
    }
    return this.crm.createStudent(actor, dto);
  }

  @Get("student-balances")
  listStudentBalances(
    @CurrentActor() actor: ActorContext,
    @Query() query: StudentBalanceQuery,
  ) {
    return this.finance.listStudentBalances(actor, query);
  }

  @Get("students/:id/groups")
  listStudentGroups(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: CrmListQuery,
  ) {
    return this.crm.listStudentGroups(actor, id, query);
  }

  @Get("students/:id/card")
  getStudentCard(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.getStudentCard(actor, id);
  }

  @Get("students/:id/ledger")
  listStudentLedger(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Query() query: StudentLedgerQuery,
  ) {
    return this.finance.listStudentLedger(actor, id, {
      direction: query.direction,
      limit: query.limit,
    });
  }

  @Post("students/:id/adjustments")
  createAccountAdjustment(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CreateAdjustmentDto,
  ) {
    return this.finance.createAccountAdjustment(actor, id, dto);
  }

  @Patch("students/:id/adjustments/:adjustmentId")
  updateAccountAdjustment(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("adjustmentId", ParseUUIDPipe) adjustmentId: string,
    @Body() dto: UpdateAdjustmentDto,
  ) {
    return this.finance.updateAccountAdjustment(actor, id, adjustmentId, dto);
  }

  // DELETE отменяет (сторнирует), а не стирает: строку личного счёта уже
  // показывали клиенту, и её исчезновение не оставило бы следа.
  @Delete("students/:id/adjustments/:adjustmentId")
  voidAccountAdjustment(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Param("adjustmentId", ParseUUIDPipe) adjustmentId: string,
  ) {
    return this.finance.voidAccountAdjustment(actor, id, adjustmentId);
  }

  @Post("students/:id/transfer")
  createAccountTransfer(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: CreateTransferDto,
  ) {
    return this.finance.createAccountTransfer(actor, id, dto);
  }

  // Отдельный эндпоинт, а не поле в PATCH students/:id: бан снимает человеку
  // доступ к чатам — такое не должно уезжать вместе с патчем произвольных
  // полей карточки. См. blacklist.service.ts.
  @Patch("students/:id/blacklist")
  setStudentBlacklist(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: SetBlacklistDto,
  ) {
    return this.blacklist.setStudentBlacklist(actor, id, dto);
  }

  @Get("students/:id")
  getStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.getStudent(actor, id);
  }

  @Patch("students/:id")
  updateStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: UpdateStudentDto,
  ) {
    return this.crm.updateStudent(actor, id, dto);
  }

  @Delete("students/:id")
  deleteStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.deleteStudent(actor, id);
  }

  @Post("students/:id/return-to-lead")
  returnStudentToLead(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.returnStudentToLead(actor, id);
  }

  @Post("students/:id/invite")
  inviteStudent(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
  ) {
    return this.crm.inviteStudent(actor, id);
  }

  @Post("students/:id/subscriptions/issue")
  issueSubscription(
    @CurrentActor() actor: ActorContext,
    @Param("id", ParseUUIDPipe) id: string,
    @Body() dto: IssueSubscriptionDto,
  ) {
    return this.subscriptions.issueSubscription(actor, id, dto);
  }
}
