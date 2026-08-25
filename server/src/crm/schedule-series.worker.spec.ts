import { ScheduleSeriesMaterializerService } from "./schedule/schedule-series-materializer.service";
import { ScheduleSeriesWorker } from "./schedule-series.worker";

describe("ScheduleSeriesWorker", () => {
  afterEach(() => {
    jest.useRealTimers();
    delete process.env.SCHEDULE_SERIES_AUTOEXTEND;
  });

  it("extends the horizon through the dedicated materializer", async () => {
    jest.useFakeTimers();
    const extendAllSeriesHorizon = jest.fn().mockResolvedValue({
      series: 1,
      created: 0,
      failed: 0,
    });
    const worker = new ScheduleSeriesWorker({
      extendAllSeriesHorizon,
    } as unknown as ScheduleSeriesMaterializerService);

    worker.onModuleInit();
    await jest.advanceTimersByTimeAsync(30_000);

    expect(extendAllSeriesHorizon).toHaveBeenCalledTimes(1);
    worker.onModuleDestroy();
  });
});
