import { MODULE_METADATA } from "@nestjs/common/constants";
import { AuthModule } from "../auth/auth.module";
import { CrmModule } from "../crm/crm.module";
import { DatabaseModule } from "../db/database.module";
import { PlatformModule } from "../platform/platform.module";
import { NotificationDeliveryModule } from "./notification-delivery.module";
import { NotificationWorker } from "./notification-worker.service";
import { NotificationsController } from "./notifications.controller";
import { NotificationsModule } from "./notifications.module";
import { NotificationsService } from "./notifications.service";

function metadata<T>(key: string, target: object): T[] {
  return (Reflect.getMetadata(key, target) as T[] | undefined) ?? [];
}

describe("notification module boundary", () => {
  it("keeps delivery providers in one controller-free module", () => {
    expect(metadata(MODULE_METADATA.PROVIDERS, NotificationDeliveryModule)).toEqual(
      expect.arrayContaining([NotificationsService, NotificationWorker]),
    );
    expect(metadata(MODULE_METADATA.CONTROLLERS, NotificationDeliveryModule)).toEqual([]);
  });

  it("keeps HTTP controllers in the API module", () => {
    expect(metadata(MODULE_METADATA.IMPORTS, NotificationsModule)).toContain(
      NotificationDeliveryModule,
    );
    expect(metadata(MODULE_METADATA.IMPORTS, NotificationsModule)).toContain(
      DatabaseModule,
    );
    expect(metadata(MODULE_METADATA.CONTROLLERS, NotificationsModule)).toContain(
      NotificationsController,
    );
    expect(metadata(MODULE_METADATA.PROVIDERS, NotificationsModule)).not.toContain(
      NotificationsService,
    );
    expect(metadata(MODULE_METADATA.PROVIDERS, NotificationsModule)).not.toContain(
      NotificationWorker,
    );
  });

  it.each([AuthModule, CrmModule, PlatformModule])(
    "%p imports delivery without mounting notification controllers",
    (consumer) => {
      const imports = metadata(MODULE_METADATA.IMPORTS, consumer);
      expect(imports).toContain(NotificationDeliveryModule);
      expect(imports).not.toContain(NotificationsModule);
    },
  );

  it.each([NotificationsService, NotificationWorker])(
    "%p has exactly one provider owner",
    (provider) => {
      const modules = [
        NotificationDeliveryModule,
        NotificationsModule,
        AuthModule,
        CrmModule,
        PlatformModule,
      ];
      const owners = modules.filter((module) =>
        metadata(MODULE_METADATA.PROVIDERS, module).includes(provider),
      );

      expect(owners).toEqual([NotificationDeliveryModule]);
    },
  );
});
