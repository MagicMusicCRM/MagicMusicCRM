import type { Type } from "@nestjs/common";
import type { NestContainer } from "@nestjs/core/injector/container";
import type { InstanceWrapper } from "@nestjs/core/injector/instance-wrapper";
import type { Module as CompiledModule } from "@nestjs/core/injector/module";
import { Test, TestingModule } from "@nestjs/testing";
import { AuthModule } from "./auth/auth.module";
import { CrmModule } from "./crm/crm.module";
import { ScheduleReadService } from "./crm/schedule/schedule-read.service";
import { DatabaseService } from "./db/database.service";
import { NotificationDeliveryModule } from "./notifications/notification-delivery.module";
import { NotificationWorker } from "./notifications/notification-worker.service";
import {
  AdminNotificationsController,
  NotificationsController,
} from "./notifications/notifications.controller";
import { NotificationsModule } from "./notifications/notifications.module";
import { NotificationsService } from "./notifications/notifications.service";
import { PlatformModule } from "./platform/platform.module";

type CompiledOwner = {
  module: CompiledModule;
  wrapper: InstanceWrapper;
};

function compiledModules(moduleRef: TestingModule): CompiledModule[] {
  const container = (moduleRef as unknown as { container: NestContainer }).container;
  return [...container.getModules().values()];
}

function expectSoleCompiledModule(
  modules: CompiledModule[],
  moduleType: Type<unknown>,
): CompiledModule {
  const matches = modules.filter((module) => module.metatype === moduleType);
  expect({
    module: moduleType.name,
    compiledCount: matches.length,
  }).toEqual({
    module: moduleType.name,
    compiledCount: 1,
  });
  return matches[0];
}

function findProviderOwners(
  modules: CompiledModule[],
  provider: Type<unknown>,
): CompiledOwner[] {
  return modules.flatMap((module) =>
    [...module.providers.values()]
      .filter(
        (wrapper) =>
          wrapper.token === provider ||
          wrapper.metatype === provider ||
          wrapper.instance instanceof provider,
      )
      .map((wrapper) => ({ module, wrapper })),
  );
}

function findControllerOwners(
  modules: CompiledModule[],
  controller: Type<unknown>,
): CompiledOwner[] {
  return modules.flatMap((module) =>
    [...module.controllers.values()]
      .filter(
        (wrapper) =>
          wrapper.token === controller ||
          wrapper.metatype === controller ||
          wrapper.instance instanceof controller,
      )
      .map((wrapper) => ({ module, wrapper })),
  );
}

function expectSoleOwner(
  token: Type<unknown>,
  owners: CompiledOwner[],
  expectedOwner: Type<unknown>,
): void {
  const instances = owners
    .map(({ wrapper }) => wrapper.instance)
    .filter((instance) => instance !== null && instance !== undefined);
  const diagnostics = {
    token: token.name,
    wrapperCount: owners.length,
    instanceCount: instances.length,
    uniqueInstanceCount: new Set(instances).size,
    owners: owners.map(({ module, wrapper }) => ({
      module: module.metatype.name,
      providerToken:
        typeof wrapper.token === "function" ? wrapper.token.name : String(wrapper.token),
    })),
  };

  expect(diagnostics).toEqual({
    token: token.name,
    wrapperCount: 1,
    instanceCount: 1,
    uniqueInstanceCount: 1,
    owners: [{ module: expectedOwner.name, providerToken: token.name }],
  });
  expect(owners[0].module.metatype).toBe(expectedOwner);
  expect(owners[0].wrapper.instance).toBeInstanceOf(token);
}

describe("AppModule", () => {
  let appModuleType: Type<unknown>;
  let moduleRef: TestingModule;
  let modules: CompiledModule[];

  beforeAll(async () => {
    process.env.DATABASE_URL = "postgresql://user:pass@localhost:5432/magiccrm";
    process.env.JWT_ACCESS_SECRET = "test-secret-test-secret-test-secret-123";
    const { AppModule } = await import("./app.module");
    appModuleType = AppModule;
    moduleRef = await Test.createTestingModule({
      imports: [AppModule],
    })
      .overrideProvider(DatabaseService)
      .useValue({
        query: jest.fn(),
        transaction: jest.fn(),
        onModuleDestroy: jest.fn(),
      })
      .compile();
    modules = compiledModules(moduleRef);
  });

  afterAll(async () => {
    await moduleRef.close();
  });

  it("resolves the dedicated schedule read service", () => {
    expect(moduleRef.get(ScheduleReadService, { strict: false })).toBeDefined();
  });

  it("mounts the notification API shell directly", () => {
    const appModule = expectSoleCompiledModule(modules, appModuleType);
    const apiImports = [...appModule.imports].filter(
      (module) => module.metatype === NotificationsModule,
    );
    expect({
      owner: appModule.metatype.name,
      notificationApiImportCount: apiImports.length,
    }).toEqual({
      owner: appModuleType.name,
      notificationApiImportCount: 1,
    });
  });

  it.each([NotificationsService, NotificationWorker])(
    "%p has one compiled provider instance owned by the delivery module",
    (provider) => {
      const owners = findProviderOwners(modules, provider);

      expectSoleOwner(provider, owners, NotificationDeliveryModule);
      const deliveryInstance = owners[0].wrapper.instance;
      expect(moduleRef.get(provider, { strict: false })).toBe(deliveryInstance);

      for (const consumer of [AuthModule, CrmModule, PlatformModule]) {
        const consumerModule = expectSoleCompiledModule(modules, consumer);
        expect([...consumerModule.imports]).toContain(owners[0].module);
        expect(moduleRef.select(consumer).get(provider, { strict: false })).toBe(
          deliveryInstance,
        );
      }
    },
  );

  it.each([NotificationsController, AdminNotificationsController])(
    "%p has one compiled owner in the API shell",
    (controller) => {
      expectSoleOwner(
        controller,
        findControllerOwners(modules, controller),
        NotificationsModule,
      );
    },
  );
});
