import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from "@nestjs/common";
import { ScheduleService } from "./schedule.service";

/**
 * KVA-236: продлевает материализацию занятий живых серий (включая
 * «до бесконечности») до горизонта. Без него бесконечная серия закончилась бы
 * на границе последней генерации. Отключается SCHEDULE_SERIES_AUTOEXTEND=false.
 */
@Injectable()
export class ScheduleSeriesWorker implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(ScheduleSeriesWorker.name);
  private timer: ReturnType<typeof setInterval> | undefined;

  constructor(private readonly schedule: ScheduleService) {}

  onModuleInit(): void {
    if (process.env.SCHEDULE_SERIES_AUTOEXTEND === "false") {
      this.logger.log("Series auto-extend disabled");
      return;
    }
    const tick = () => {
      void this.schedule
        .extendAllSeriesHorizon()
        .then(({ series, created }) => {
          if (created > 0) {
            this.logger.log(`Series extended: ${created} lessons across ${series} series`);
          }
        })
        .catch((error: unknown) => {
          this.logger.error(
            `Series extend tick failed: ${error instanceof Error ? error.name : "unknown"}`,
          );
        });
    };
    // Первый прогон после старта + каждые 6 часов.
    setTimeout(tick, 30_000).unref?.();
    this.timer = setInterval(tick, 6 * 3600_000);
    this.timer.unref?.();
    this.logger.log("Schedule series auto-extend started (every 6h)");
  }

  onModuleDestroy(): void {
    if (this.timer) clearInterval(this.timer);
  }
}
