import {
  BadRequestException,
  ConflictException,
  Injectable,
  NotFoundException,
  UnprocessableEntityException,
} from "@nestjs/common";
import { createHash } from "crypto";
import { PoolClient } from "pg";
import { ActorContext } from "../../common/security/actor-context";
import { PlatformIntegrityService } from "../../platform/platform-integrity.service";
import { PlatformAuditInput } from "../../platform/platform-integrity.types";
import { CrmPolicy } from "../crm.policy";
import { SubscriptionPackageListQuery } from "../dto/subscription-package.query";
import { UpdateSubscriptionPackageDto } from "../dto/update-subscription-package.dto";
import { UpsertSubscriptionPackageDto } from "../dto/upsert-subscription-package.dto";
import {
  PackageCatalogRepository,
  SubscriptionPackageRow,
  SubscriptionPackageValues,
} from "./package-catalog.repository";

interface MutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

export interface SubscriptionPackageDto extends Record<string, unknown> {
  id: string;
  name: string;
  disciplineId: string | null;
  branchId: string | null;
  branchName: string | null;
  unitCount: number;
  lessonsTotal: number;
  basePriceMinor: string;
  price: number;
  currencyCode: string;
  validityDays: number | null;
  active: boolean;
  isActive: boolean;
  sortOrder: number;
  version: number;
  createdAt: Date | string;
  updatedAt: Date | string;
  archivedAt: Date | string | null;
}

interface PackageMutationResult extends Record<string, unknown> {
  packageId: string;
  packageVersion: number;
}

const aggregateType = "commerce:subscription-package";
const mutationFields = [
  "name",
  "disciplineId",
  "branchId",
  "lessonsTotal",
  "unitCount",
  "price",
  "basePriceMinor",
  "currencyCode",
  "validityDays",
  "sortOrder",
] as const;

@Injectable()
export class PackageCatalogService {
  constructor(
    private readonly repository: PackageCatalogRepository,
    private readonly policy: CrmPolicy,
    private readonly integrity: PlatformIntegrityService,
  ) {}

  async list(
    actor: ActorContext,
    query: SubscriptionPackageListQuery,
  ) {
    this.policy.assertCanReadSubscriptionPackages(actor);
    const includeArchived = query.includeArchived ?? false;
    if (includeArchived) {
      this.policy.assertCanManageSubscriptionPackages(actor);
    }
    const items = await this.repository.list({
      query: query.q?.trim() || undefined,
      includeArchived,
      limit: Math.min(query.limit ?? 100, 200),
    });
    return { items: items.map((row) => this.toDto(row)) };
  }

  async create(
    actor: ActorContext,
    dto: UpsertSubscriptionPackageDto,
    metadata: MutationMetadata,
  ): Promise<SubscriptionPackageDto> {
    this.policy.assertCanManageSubscriptionPackages(actor);
    this.assertMetadata(metadata);
    const values = this.createValues(dto);
    const packageId = this.deterministicPackageId(
      actor.userId,
      metadata.idempotencyKey,
    );
    const audit: PlatformAuditInput = {
      action: "crm.subscription_package_created",
      entityType: "subscription_package",
      entityId: packageId,
      metadata: { lifecycle: "created" },
    };
    const result =
      await this.integrity.executeVersionedMutation<PackageMutationResult>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        authorization: {
          actor,
          capabilityKey: "config.commerce.manage",
        },
        operation: "crm.subscription-package.create",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType,
        aggregateId: packageId,
        expectedVersion: 0,
        payload: values,
        audit,
        outbox: {
          type: "commerce.package.changed",
          payload: {
            entityId: packageId,
            action: "created",
            changedFields: mutationFields,
          },
        },
        mutate: async (client, nextVersion) => {
          const created = await this.repository.create(
            client,
            packageId,
            nextVersion,
            values,
          );
          audit.afterRef = this.auditRef(created);
          return {
            packageId: created.id,
            packageVersion: Number(created.version),
          };
        },
      });
    return this.loadVersionDto(
      result.resultRef.packageId,
      result.resultRef.packageVersion,
    );
  }

  async update(
    actor: ActorContext,
    packageId: string,
    dto: UpdateSubscriptionPackageDto,
    metadata: MutationMetadata,
  ): Promise<SubscriptionPackageDto> {
    this.policy.assertCanManageSubscriptionPackages(actor);
    this.assertMetadata(metadata);
    this.assertMutablePatch(dto);
    await this.requireExisting(packageId);

    const audit: PlatformAuditInput = {
      action: "crm.subscription_package_updated",
      entityType: "subscription_package",
      entityId: packageId,
      metadata: { lifecycle: "updated" },
    };
    const result =
      await this.integrity.executeVersionedMutation<PackageMutationResult>({
        actorKey: actor.userId,
        actorUserId: actor.userId,
        authorization: {
          actor,
          capabilityKey: "config.commerce.manage",
        },
        operation: "crm.subscription-package.update",
        idempotencyKey: metadata.idempotencyKey,
        requestId: metadata.requestId,
        aggregateType,
        aggregateId: packageId,
        expectedVersion: dto.expectedVersion,
        payload: { packageId, ...dto },
        audit,
        outbox: {
          type: "commerce.package.changed",
          payload: {
            entityId: packageId,
            action: "updated",
            changedFields: mutationFields.filter(
              (field) => dto[field] !== undefined,
            ),
          },
        },
        mutate: async (client, nextVersion) => {
          const before = await this.requireCurrent(client, packageId);
          this.assertCurrentVersion(before, dto.expectedVersion, nextVersion);
          if (before.deleted_at !== null || !before.is_active) {
            throw new ConflictException({
              code: "PACKAGE_ARCHIVED",
              message: "Архивный пакет сначала нужно восстановить.",
            });
          }
          const values = this.mergeValues(before, dto);
          if (this.valuesEqual(before, values)) {
            throw new UnprocessableEntityException({
              code: "PACKAGE_UNCHANGED",
              message: "Изменения пакета не указаны.",
            });
          }
          audit.beforeRef = this.auditRef(before);
          const updated = await this.repository.update(
            client,
            packageId,
            dto.expectedVersion,
            nextVersion,
            values,
          );
          if (!updated) this.throwStale(dto.expectedVersion, before);
          audit.afterRef = this.auditRef(updated!);
          return {
            packageId: updated!.id,
            packageVersion: Number(updated!.version),
          };
        },
      });
    return this.loadVersionDto(
      result.resultRef.packageId,
      result.resultRef.packageVersion,
    );
  }

  async archive(
    actor: ActorContext,
    packageId: string,
    expectedVersion: number,
    metadata: MutationMetadata,
  ): Promise<SubscriptionPackageDto> {
    this.policy.assertCanManageSubscriptionPackages(actor);
    this.assertMetadata(metadata);
    await this.requireExisting(packageId);

    const audit: PlatformAuditInput = {
      action: "crm.subscription_package_archived",
      entityType: "subscription_package",
      entityId: packageId,
      metadata: { lifecycle: "archived" },
    };
    const result = await this.integrity.executeVersionedMutation<PackageMutationResult>({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      authorization: {
        actor,
        capabilityKey: "config.commerce.manage",
      },
      operation: "crm.subscription-package.archive",
      idempotencyKey: metadata.idempotencyKey,
      requestId: metadata.requestId,
      aggregateType,
      aggregateId: packageId,
      expectedVersion,
      payload: { packageId, expectedVersion },
      audit,
      outbox: {
        type: "commerce.package.changed",
        payload: {
          entityId: packageId,
          action: "archived",
          changedFields: ["active", "archivedAt"],
        },
      },
      mutate: async (client, nextVersion) => {
        const before = await this.requireCurrent(client, packageId);
        this.assertCurrentVersion(before, expectedVersion, nextVersion);
        if (before.deleted_at !== null || !before.is_active) {
          throw new ConflictException({
            code: "PACKAGE_ALREADY_ARCHIVED",
            message: "Пакет уже находится в архиве.",
          });
        }
        audit.beforeRef = this.auditRef(before);
        const archived = await this.repository.archive(
          client,
          packageId,
          expectedVersion,
          nextVersion,
        );
        if (!archived) this.throwStale(expectedVersion, before);
        audit.afterRef = this.auditRef(archived!);
        return {
          packageId: archived!.id,
          packageVersion: Number(archived!.version),
        };
      },
    });
    return this.loadVersionDto(
      result.resultRef.packageId,
      result.resultRef.packageVersion,
    );
  }

  async restore(
    actor: ActorContext,
    packageId: string,
    expectedVersion: number,
    metadata: MutationMetadata,
  ): Promise<SubscriptionPackageDto> {
    this.policy.assertCanManageSubscriptionPackages(actor);
    this.assertMetadata(metadata);
    await this.requireExisting(packageId);

    const audit: PlatformAuditInput = {
      action: "crm.subscription_package_restored",
      entityType: "subscription_package",
      entityId: packageId,
      metadata: { lifecycle: "restored" },
    };
    const result = await this.integrity.executeVersionedMutation<PackageMutationResult>({
      actorKey: actor.userId,
      actorUserId: actor.userId,
      authorization: {
        actor,
        capabilityKey: "config.commerce.manage",
      },
      operation: "crm.subscription-package.restore",
      idempotencyKey: metadata.idempotencyKey,
      requestId: metadata.requestId,
      aggregateType,
      aggregateId: packageId,
      expectedVersion,
      payload: { packageId, expectedVersion },
      audit,
      outbox: {
        type: "commerce.package.changed",
        payload: {
          entityId: packageId,
          action: "restored",
          changedFields: ["active", "archivedAt"],
        },
      },
      mutate: async (client, nextVersion) => {
        const before = await this.requireCurrent(client, packageId);
        this.assertCurrentVersion(before, expectedVersion, nextVersion);
        if (before.deleted_at === null && before.is_active) {
          throw new ConflictException({
            code: "PACKAGE_NOT_ARCHIVED",
            message: "Пакет не находится в архиве.",
          });
        }
        audit.beforeRef = this.auditRef(before);
        const restored = await this.repository.restore(
          client,
          packageId,
          expectedVersion,
          nextVersion,
        );
        if (!restored) this.throwStale(expectedVersion, before);
        audit.afterRef = this.auditRef(restored!);
        return {
          packageId: restored!.id,
          packageVersion: Number(restored!.version),
        };
      },
    });
    return this.loadVersionDto(
      result.resultRef.packageId,
      result.resultRef.packageVersion,
    );
  }

  private async requireExisting(
    packageId: string,
  ): Promise<SubscriptionPackageRow> {
    const row = await this.repository.findById(packageId);
    if (!row) throw new NotFoundException("Абонемент не найден.");
    return row;
  }

  private async loadVersionDto(
    packageId: string,
    version: number,
  ): Promise<SubscriptionPackageDto> {
    const row = await this.repository.findVersion(packageId, version);
    if (!row) {
      throw new ConflictException({
        code: "PACKAGE_VERSION_RESULT_MISSING",
        message: "Зафиксированная версия результата пакета не найдена.",
        packageId,
        version,
      });
    }
    return this.toDto(row);
  }

  private async requireCurrent(
    client: PoolClient,
    packageId: string,
  ): Promise<SubscriptionPackageRow> {
    const row = await this.repository.findForUpdate(client, packageId);
    if (!row) throw new NotFoundException("Абонемент не найден.");
    return row;
  }

  private assertCurrentVersion(
    current: SubscriptionPackageRow,
    expectedVersion: number,
    nextVersion: number,
  ): void {
    if (
      Number(current.version) !== expectedVersion ||
      nextVersion !== expectedVersion + 1
    ) {
      this.throwStale(expectedVersion, current);
    }
  }

  private throwStale(
    expectedVersion: number,
    current: SubscriptionPackageRow,
  ): never {
    throw new ConflictException({
      code: "STALE_VERSION",
      message: "Пакет уже изменён в другой вкладке.",
      expectedVersion,
      currentVersion: Number(current.version),
    });
  }

  private createValues(
    dto: UpsertSubscriptionPackageDto,
  ): SubscriptionPackageValues {
    return {
      name: this.requiredName(dto.name),
      disciplineId: dto.disciplineId ?? null,
      branchId: dto.branchId ?? null,
      lessonsTotal: this.resolveUnitCount(
        dto.unitCount,
        dto.lessonsTotal,
        true,
      )!,
      basePriceMinor: this.resolveBasePriceMinor(
        dto.basePriceMinor,
        dto.price,
        true,
      )!,
      currencyCode: dto.currencyCode ?? "RUB",
      validityDays: dto.validityDays ?? null,
      sortOrder: dto.sortOrder ?? 0,
    };
  }

  private mergeValues(
    current: SubscriptionPackageRow,
    dto: UpdateSubscriptionPackageDto,
  ): SubscriptionPackageValues {
    return {
      name:
        dto.name === undefined
          ? current.name
          : this.requiredName(dto.name),
      disciplineId:
        dto.disciplineId === undefined
          ? current.discipline_id
          : dto.disciplineId,
      branchId:
        dto.branchId === undefined ? current.branch_id : dto.branchId,
      lessonsTotal:
        this.resolveUnitCount(dto.unitCount, dto.lessonsTotal, false) ??
        Number(current.lessons_total),
      basePriceMinor:
        this.resolveBasePriceMinor(
          dto.basePriceMinor,
          dto.price,
          false,
        ) ?? current.base_price_minor,
      currencyCode: dto.currencyCode ?? current.currency_code,
      validityDays:
        dto.validityDays === undefined
          ? current.validity_days
          : dto.validityDays,
      sortOrder: dto.sortOrder ?? current.sort_order,
    };
  }

  private resolveUnitCount(
    unitCount: number | undefined,
    lessonsTotal: number | undefined,
    required: boolean,
  ): number | undefined {
    if (
      unitCount !== undefined &&
      lessonsTotal !== undefined &&
      unitCount !== lessonsTotal
    ) {
      throw new UnprocessableEntityException({
        code: "PACKAGE_UNIT_COUNT_AMBIGUOUS",
        field: "unitCount",
        message: "unitCount и lessonsTotal должны совпадать.",
      });
    }
    const value = unitCount ?? lessonsTotal;
    if (required && value === undefined) {
      throw new UnprocessableEntityException({
        code: "PACKAGE_UNIT_COUNT_REQUIRED",
        field: "unitCount",
        message: "Укажите количество занятий.",
      });
    }
    return value;
  }

  private resolveBasePriceMinor(
    basePriceMinor: string | undefined,
    price: number | undefined,
    required: boolean,
  ): string | undefined {
    const legacyMinor =
      price === undefined ? undefined : Math.round(price * 100);
    if (
      legacyMinor !== undefined &&
      (!Number.isSafeInteger(legacyMinor) || legacyMinor < 0)
    ) {
      throw new UnprocessableEntityException({
        code: "PACKAGE_PRICE_OUT_OF_RANGE",
        field: "price",
        message: "Цена выходит за допустимый диапазон.",
      });
    }
    if (
      basePriceMinor !== undefined &&
      legacyMinor !== undefined &&
      BigInt(basePriceMinor) !== BigInt(legacyMinor)
    ) {
      throw new UnprocessableEntityException({
        code: "PACKAGE_PRICE_AMBIGUOUS",
        field: "basePriceMinor",
        message: "basePriceMinor и price должны совпадать.",
      });
    }
    const value =
      basePriceMinor ?? (legacyMinor === undefined ? undefined : String(legacyMinor));
    if (required && value === undefined) {
      throw new UnprocessableEntityException({
        code: "PACKAGE_PRICE_REQUIRED",
        field: "basePriceMinor",
        message: "Укажите цену пакета.",
      });
    }
    if (
      value !== undefined &&
      BigInt(value) > 999999999999n
    ) {
      throw new UnprocessableEntityException({
        code: "PACKAGE_PRICE_OUT_OF_RANGE",
        field: "basePriceMinor",
        message: "Цена выходит за допустимый диапазон.",
      });
    }
    return value;
  }

  private requiredName(value: string): string {
    const name = value.trim();
    if (!name) {
      throw new UnprocessableEntityException({
        code: "REQUIRED",
        field: "name",
        message: "Укажите название абонемента.",
      });
    }
    return name;
  }

  private assertMutablePatch(dto: UpdateSubscriptionPackageDto): void {
    if (!mutationFields.some((field) => dto[field] !== undefined)) {
      throw new UnprocessableEntityException({
        code: "PACKAGE_PATCH_EMPTY",
        message: "Укажите хотя бы одно изменение пакета.",
      });
    }
  }

  private valuesEqual(
    current: SubscriptionPackageRow,
    values: SubscriptionPackageValues,
  ): boolean {
    return (
      current.name === values.name &&
      current.discipline_id === values.disciplineId &&
      current.branch_id === values.branchId &&
      Number(current.lessons_total) === values.lessonsTotal &&
      current.base_price_minor === values.basePriceMinor &&
      current.currency_code === values.currencyCode &&
      current.validity_days === values.validityDays &&
      current.sort_order === values.sortOrder
    );
  }

  private assertMetadata(metadata: MutationMetadata): void {
    if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
      throw new BadRequestException({
        code: "INVALID_IDEMPOTENCY_KEY",
        message: "Idempotency-Key должен содержать 8–160 безопасных символов.",
      });
    }
    if (
      !metadata.requestId ||
      metadata.requestId.length > 128 ||
      /[\r\n]/.test(metadata.requestId)
    ) {
      throw new BadRequestException({
        code: "INVALID_REQUEST_ID",
        message: "X-Request-Id обязателен и не должен превышать 128 символов.",
      });
    }
  }

  private deterministicPackageId(
    actorUserId: string,
    idempotencyKey: string,
  ): string {
    const hex = createHash("sha256")
      .update(`${actorUserId}\0crm.subscription-package.create\0${idempotencyKey}`)
      .digest("hex")
      .slice(0, 32)
      .split("");
    hex[12] = "4";
    hex[16] = ["8", "9", "a", "b"][parseInt(hex[16]!, 16) % 4]!;
    const value = hex.join("");
    return [
      value.slice(0, 8),
      value.slice(8, 12),
      value.slice(12, 16),
      value.slice(16, 20),
      value.slice(20),
    ].join("-");
  }

  private auditRef(
    row: SubscriptionPackageRow,
  ): Record<string, unknown> {
    return {
      packageId: row.id,
      version: Number(row.version),
      active: row.is_active && row.deleted_at === null,
      archived: row.deleted_at !== null || !row.is_active,
    };
  }

  private toDto(row: SubscriptionPackageRow): SubscriptionPackageDto {
    const active = row.is_active && row.deleted_at === null;
    return {
      id: row.id,
      name: row.name,
      disciplineId: row.discipline_id,
      branchId: row.branch_id,
      branchName: row.branch_name ?? null,
      unitCount: Number(row.lessons_total),
      lessonsTotal: Number(row.lessons_total),
      basePriceMinor: row.base_price_minor,
      price: Number(row.price),
      currencyCode: row.currency_code,
      validityDays: row.validity_days,
      active,
      isActive: active,
      sortOrder: row.sort_order,
      version: Number(row.version),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
      archivedAt: row.deleted_at,
    };
  }
}
