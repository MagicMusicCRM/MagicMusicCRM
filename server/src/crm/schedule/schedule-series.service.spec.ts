import { BadRequestException } from "@nestjs/common";
import { AuditService } from "../../audit/audit.service";
import { DatabaseService } from "../../db/database.service";
import { RealtimeBus } from "../../realtime/realtime-bus";
import { CrmPolicy } from "../crm.policy";
import { ScheduleSeriesMaterializerService } from "./schedule-series-materializer.service";
import { ScheduleSeriesService } from "./schedule-series.service";

describe("ScheduleSeriesService", () => {
  const actor = { userId: "manager-a", role: "manager" as const };

  it("uses Moscow business dates across the UTC midnight boundary", () => {
    jest.useFakeTimers();
    try {
      jest.setSystemTime(new Date("2026-07-17T21:30:00.000Z"));
      const service = Object.create(
        ScheduleSeriesService.prototype,
      ) as ScheduleSeriesService;
      const businessDate = service as unknown as {
        moscowDate(offsetDays?: number): string;
      };

      expect(businessDate.moscowDate()).toBe("2026-07-18");
      expect(businessDate.moscowDate(1)).toBe("2026-07-19");
    } finally {
      jest.useRealTimers();
    }
  });

  it("rejects past edit and stop cutoffs before opening a transaction", async () => {
    jest.useFakeTimers();
    try {
      jest.setSystemTime(new Date("2026-07-18T09:00:00.000Z"));
      const query = jest.fn();
      const service = new ScheduleSeriesService(
        { query, transaction: jest.fn() } as unknown as DatabaseService,
        { record: jest.fn() } as unknown as AuditService,
        { assertCanWriteCrm: jest.fn() } as unknown as CrmPolicy,
        { emitCrmChanged: jest.fn() } as unknown as RealtimeBus,
        {} as ScheduleSeriesMaterializerService,
      );

      await expect(
        service.updateScheduleSeries(actor, "series-a", {
          effectiveFrom: "2026-07-17",
        }),
      ).rejects.toBeInstanceOf(BadRequestException);
      await expect(
        service.deleteScheduleSeries(actor, "series-a", "2026-07-17"),
      ).rejects.toBeInstanceOf(BadRequestException);
      expect(query).not.toHaveBeenCalled();
    } finally {
      jest.useRealTimers();
    }
  });
});
