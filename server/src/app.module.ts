import { MiddlewareConsumer, Module, NestModule } from "@nestjs/common";
import { ConfigModule } from "@nestjs/config";
import { AuditModule } from "./audit/audit.module";
import { AuthModule } from "./auth/auth.module";
import { RequestIdMiddleware } from "./common/middleware/request-id.middleware";
import { SafeLogger } from "./common/logging/safe-logger.service";
import { envValidationSchema } from "./config/env.validation";
import { AnalyticsModule } from "./analytics/analytics.module";
import { CrmModule } from "./crm/crm.module";
import { DatabaseModule } from "./db/database.module";
import { FilesModule } from "./files/files.module";
import { HealthModule } from "./health/health.module";
import { LegalModule } from "./legal/legal.module";
import { MessengerModule } from "./messenger/messenger.module";
import { NotificationsModule } from "./notifications/notifications.module";
import { ProfileModule } from "./profile/profile.module";
import { SettingsModule } from "./settings/settings.module";

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      validationSchema: envValidationSchema,
    }),
    DatabaseModule,
    AuditModule,
    AuthModule,
    ProfileModule,
    CrmModule,
    AnalyticsModule,
    MessengerModule,
    FilesModule,
    LegalModule,
    NotificationsModule,
    SettingsModule,
    HealthModule,
  ],
  providers: [SafeLogger],
  exports: [SafeLogger],
})
export class AppModule implements NestModule {
  configure(consumer: MiddlewareConsumer) {
    consumer.apply(RequestIdMiddleware).forRoutes("*");
  }
}
