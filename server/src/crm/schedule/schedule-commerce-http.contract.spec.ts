import {
  ConflictException,
  ExecutionContext,
  ForbiddenException,
  INestApplication,
  NotFoundException,
  UnauthorizedException,
  ValidationPipe,
} from "@nestjs/common";
import { Test } from "@nestjs/testing";
import type { AddressInfo } from "node:net";
import { SafeExceptionFilter } from "../../common/filters/safe-exception.filter";
import { JwtAuthGuard } from "../../common/security/jwt-auth.guard";
import { CrmConfigurationController } from "../crm-configuration.controller";
import { CrmConfigurationService } from "../crm-configuration.service";
import { CrmScheduleController } from "../crm-schedule.controller";
import { LessonSettlementCalculationError } from "../commerce/lesson-settlement.calculation";
import { SubscriptionPreviewTokenError } from "../commerce/subscription-preview-token";
import { LessonSettlementCorrectionService } from "./lesson-settlement-correction.service";
import { LessonCommandService } from "./lesson-command.service";
import { LessonScheduleMutationService } from "./lesson-schedule-mutation.service";
import { LessonTeacherRateService } from "./lesson-teacher-rate.service";
import { LessonTransitionService } from "./lesson-transition.service";
import { ScheduleConflictService } from "./schedule-conflict.service";
import { SchedulePlanService } from "./schedule-plan.service";
import { ScheduleReadService } from "./schedule-read.service";
import { ScheduleSeriesService } from "./schedule-series.service";
import { StudentLessonTimelineService } from "./student-lesson-timeline.service";
import { V4DomainFlagsService } from "../../platform/rollout/v4/domain-flags";

const IDS = {
  actor: "10000000-0000-4000-8000-000000000001",
  student: "10000000-0000-4000-8000-000000000002",
  crossOrgStudent: "10000000-0000-4000-8000-000000000003",
  plan: "10000000-0000-4000-8000-000000000004",
  series: "10000000-0000-4000-8000-000000000005",
  lesson: "10000000-0000-4000-8000-000000000006",
  rescheduledSource: "10000000-0000-4000-8000-000000000007",
  teacher: "10000000-0000-4000-8000-000000000008",
  branch: "10000000-0000-4000-8000-000000000009",
  room: "10000000-0000-4000-8000-000000000010",
  subscription: "10000000-0000-4000-8000-000000000011",
} as const;

const financialDecision = {
  settlementTypeKey: "paid_lesson",
  clientDecisions: [{
    clientId: IDS.student,
    settlementTypeKey: "paid_lesson",
    chargeType: "subscription",
    chargeDurationMinutes: 60,
    subscriptionId: IDS.subscription,
  }],
  teacherCompensationRuleKey: "standard",
  teacherCreditedDurationMinutes: 60,
};

const cancelPreview = {
  expectedVersion: 4,
  reasonCode: "client.cancelled",
  reasonText: "Клиент отменил занятие",
  financialDecision,
};

const movePreview = {
  expectedVersion: 4,
  reasonCode: "client.rescheduled",
  reasonText: "Клиент выбрал другое время",
  successor: {
    studentId: IDS.student,
    teacherId: IDS.teacher,
    branchId: IDS.branch,
    roomId: IDS.room,
    scheduledAt: "2026-09-11T12:00:00.000Z",
    durationMinutes: 60,
  },
  successorFinancialDecision: financialDecision,
};

type HttpCase = {
  name: string;
  method: "GET" | "POST" | "PUT";
  path: string;
  body?: Record<string, unknown>;
  status: number;
  code?: string;
};

const CASES: HttpCase[] = [
  {
    name: "global student timeline",
    method: "GET",
    path: `/crm/students/${IDS.student}/lesson-timeline`,
    status: 200,
  },
  {
    name: "signed row removal preview",
    method: "POST",
    path: `/crm/schedule-plans/${IDS.plan}/rows/${IDS.series}/remove/preview`,
    body: { expectedVersion: 4, reasonText: "Смена дня занятий" },
    status: 201,
  },
  {
    name: "lesson cancellation preview",
    method: "POST",
    path: `/crm/lessons/${IDS.lesson}/cancel/preview`,
    body: cancelPreview,
    status: 201,
  },
  {
    name: "lesson reschedule preview",
    method: "POST",
    path: `/crm/lessons/${IDS.lesson}/reschedule/preview`,
    body: movePreview,
    status: 201,
  },
  {
    name: "invalid independent partial duration",
    method: "POST",
    path: `/crm/lessons/${IDS.lesson}/settle/preview`,
    body: {
      expectedVersion: 4,
      financialDecision: {
        ...financialDecision,
        clientDecisions: [{
          ...financialDecision.clientDecisions[0],
          chargeDurationMinutes: 61,
        }],
      },
    },
    status: 422,
    code: "PARTIAL_DURATION_EXCEEDS_LESSON",
  },
  {
    name: "stale recurring row version",
    method: "POST",
    path: `/crm/schedule-plans/${IDS.plan}/rows/${IDS.series}/remove`,
    body: {
      expectedVersion: 3,
      reasonText: "Смена дня занятий",
      previewToken: "signed-preview",
      confirm: true,
    },
    status: 409,
    code: "SCHEDULE_PLAN_VERSION_STALE",
  },
  {
    name: "stale transition preview token",
    method: "POST",
    path: `/crm/lessons/${IDS.lesson}/cancel`,
    body: {
      ...cancelPreview,
      previewToken: "expired-preview",
      confirm: true,
    },
    status: 422,
    code: "PREVIEW_TOKEN_EXPIRED",
  },
  {
    name: "forbidden system settlement catalog edit",
    method: "PUT",
    path: "/crm/configuration/draft",
    body: { baseVersion: 7, snapshot: { lessonSettlementTypes: [] } },
    status: 403,
    code: "SYSTEM_SETTLEMENT_POLICY_READ_ONLY",
  },
  {
    name: "cross-organization student is concealed",
    method: "GET",
    path: `/crm/students/${IDS.crossOrgStudent}/lesson-timeline`,
    status: 404,
    code: "STUDENT_NOT_FOUND",
  },
  {
    name: "already-rescheduled source is a typed conflict",
    method: "POST",
    path: `/crm/lessons/${IDS.rescheduledSource}/reschedule`,
    body: {
      ...movePreview,
      previewToken: "signed-preview",
      confirm: true,
    },
    status: 409,
    code: "LESSON_ALREADY_RESCHEDULED",
  },
  {
    name: "concurrent reservation change is a typed conflict",
    method: "POST",
    path: `/crm/lessons/${IDS.lesson}/settle`,
    body: {
      expectedVersion: 4,
      financialDecision,
      previewToken: "signed-preview",
      confirm: true,
    },
    status: 409,
    code: "SUBSCRIPTION_RESERVATION_CONFLICT",
  },
];

describe("unified schedule-commerce authenticated HTTP contracts", () => {
  let app: INestApplication;
  let baseUrl: string;
  const statuses: number[] = [];

  beforeAll(async () => {
    const studentLessonTimelines = {
      list: jest.fn(async (_actor, studentId: string) => {
        if (studentId === IDS.crossOrgStudent) {
          throw new NotFoundException({
            code: "STUDENT_NOT_FOUND",
            message: "Ученик не найден.",
          });
        }
        return {
          items: [], previousCursor: null, nextCursor: null,
          hasPrevious: false, hasNext: false,
        };
      }),
    };
    const schedulePlans = {
      previewRemoveRow: jest.fn(async () => ({ previewToken: "signed" })),
      removeRow: jest.fn(async () => {
        throw new ConflictException({
          code: "SCHEDULE_PLAN_VERSION_STALE",
          message: "Расписание уже изменено. Обновите данные.",
        });
      }),
    };
    const lessonTransitions = {
      previewCancel: jest.fn(async () => ({ previewToken: "signed" })),
      previewReschedule: jest.fn(async () => ({ previewToken: "signed" })),
      previewSettle: jest.fn(async () => {
        throw new LessonSettlementCalculationError(
          "PARTIAL_DURATION_EXCEEDS_LESSON",
        );
      }),
      cancel: jest.fn(async () => {
        throw new SubscriptionPreviewTokenError("PREVIEW_TOKEN_EXPIRED");
      }),
      reschedule: jest.fn(async (_actor, lessonId: string) => {
        if (lessonId === IDS.rescheduledSource) {
          throw new ConflictException({
            code: "LESSON_ALREADY_RESCHEDULED",
            message: "Занятие уже перенесено. Откройте актуальное занятие.",
          });
        }
      }),
      settle: jest.fn(async () => {
        throw new ConflictException({
          code: "SUBSCRIPTION_RESERVATION_CONFLICT",
          message: "Резерв абонемента уже изменился. Обновите расчёт.",
        });
      }),
    };
    const configuration = {
      saveDraft: jest.fn(async () => {
        throw new ForbiddenException({
          code: "SYSTEM_SETTLEMENT_POLICY_READ_ONLY",
          message: "Системные правила расчёта доступны только для чтения.",
        });
      }),
    };
    const moduleRef = await Test.createTestingModule({
      controllers: [CrmScheduleController, CrmConfigurationController],
      providers: [
        { provide: LessonScheduleMutationService, useValue: {} },
        { provide: LessonTeacherRateService, useValue: {} },
        { provide: ScheduleReadService, useValue: {} },
        { provide: ScheduleConflictService, useValue: {} },
        { provide: ScheduleSeriesService, useValue: {} },
        { provide: LessonCommandService, useValue: {} },
        { provide: LessonTransitionService, useValue: lessonTransitions },
        {
          provide: V4DomainFlagsService,
          useValue: {
            get: jest.fn(() => ({ effectivePath: "v4" })),
            assertEnabled: jest.fn(),
          },
        },
        { provide: SchedulePlanService, useValue: schedulePlans },
        { provide: LessonSettlementCorrectionService, useValue: {} },
        { provide: StudentLessonTimelineService, useValue: studentLessonTimelines },
        { provide: CrmConfigurationService, useValue: configuration },
      ],
    })
      .overrideGuard(JwtAuthGuard)
      .useValue({
        canActivate: (context: ExecutionContext) => {
          const request = context.switchToHttp().getRequest();
          if (request.headers.authorization !== "Bearer contract-token") {
            throw new UnauthorizedException({
              code: "AUTH_REQUIRED",
              message: "Требуется авторизация.",
            });
          }
          request.user = { userId: IDS.actor, role: "director" };
          return true;
        },
      })
      .compile();

    app = moduleRef.createNestApplication();
    app.setGlobalPrefix("api");
    app.useGlobalPipes(new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }));
    app.useGlobalFilters(new SafeExceptionFilter({
      error: jest.fn(),
      warn: jest.fn(),
    } as never));
    await app.listen(0, "127.0.0.1");
    const address = app.getHttpServer().address() as AddressInfo;
    baseUrl = `http://127.0.0.1:${address.port}/api`;
  });

  afterAll(async () => {
    await app.close();
    expect(statuses.filter((status) => status >= 500)).toEqual([]);
  });

  it.each(CASES)("$method $name returns $status without 500", async (testCase) => {
    const response = await fetch(`${baseUrl}${testCase.path}`, {
      method: testCase.method,
      headers: {
        authorization: "Bearer contract-token",
        "content-type": "application/json",
        "x-request-id": `contract-${testCase.name.replaceAll(" ", "-")}`,
      },
      body: testCase.body === undefined ? undefined : JSON.stringify(testCase.body),
    });
    const payload = await response.json() as Record<string, unknown>;
    statuses.push(response.status);

    expect(response.status).toBe(testCase.status);
    expect(response.status).toBeLessThan(500);
    if (testCase.code) {
      expect(payload.code).toBe(testCase.code);
      expect(payload.message).toEqual(expect.stringMatching(/[А-Яа-яЁё]/));
      expect(payload.requestId).toEqual(expect.stringMatching(/^contract-/));
      expect(JSON.stringify(payload)).not.toMatch(/SELECT |violates|stack|token=/i);
    }
  });
});
