import { MODULE_METADATA } from "@nestjs/common/constants";
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
    expect(metadata(MODULE_METADATA.CONTROLLERS, NotificationsModule)).toContain(
      NotificationsController,
    );
    expect(metadata(MODULE_METADATA.PROVIDERS, NotificationsModule)).not.toContain(
      NotificationsService,
    );
  });
});
