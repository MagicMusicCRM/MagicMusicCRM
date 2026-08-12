import { Injectable } from "@nestjs/common";
import { PoolClient } from "pg";
import { DatabaseService } from "../../db/database.service";

export interface SubscriptionPackageRow {
  id: string;
  name: string;
  discipline_id: string | null;
  branch_id: string | null;
  branch_name?: string | null;
  lessons_total: string | number;
  price: string | number;
  base_price_minor: string;
  currency_code: string;
  validity_days: number | null;
  is_active: boolean;
  sort_order: number;
  version: number | string;
  created_at: Date | string;
  updated_at: Date | string;
  deleted_at: Date | string | null;
}

export interface SubscriptionPackageValues {
  name: string;
  disciplineId: string | null;
  branchId: string | null;
  lessonsTotal: number;
  basePriceMinor: string;
  currencyCode: string;
  validityDays: number | null;
  sortOrder: number;
}

const packageProjection = `
  id,
  name,
  discipline_id,
  branch_id,
  lessons_total,
  price,
  base_price_minor,
  currency_code,
  validity_days,
  is_active,
  sort_order,
  version,
  created_at,
  updated_at,
  deleted_at
`;

@Injectable()
export class PackageCatalogRepository {
  constructor(private readonly database: DatabaseService) {}

  async findById(
    packageId: string,
  ): Promise<SubscriptionPackageRow | null> {
    const result = await this.database.query<SubscriptionPackageRow>(
      `
        select
          ${packageProjection},
          (
            select branch.name
            from app.branches branch
            where branch.id = app.subscription_packages.branch_id
          ) as branch_name
        from app.subscription_packages
        where id = $1
      `,
      [packageId],
    );
    return result.rows[0] ?? null;
  }

  async findVersion(
    packageId: string,
    version: number,
  ): Promise<SubscriptionPackageRow | null> {
    const result = await this.database.query<SubscriptionPackageRow>(
      `
        select
          package_id as id,
          name,
          discipline_id,
          branch_id,
          unit_count as lessons_total,
          price,
          base_price_minor,
          currency_code,
          validity_days,
          is_active,
          sort_order,
          version,
          package_created_at as created_at,
          package_updated_at as updated_at,
          archived_at as deleted_at
        from app.subscription_package_versions
        where package_id = $1 and version = $2
      `,
      [packageId, version],
    );
    return result.rows[0] ?? null;
  }

  async list(
    input: {
      query?: string;
      includeArchived: boolean;
      limit: number;
    },
  ): Promise<SubscriptionPackageRow[]> {
    const result = await this.database.query<SubscriptionPackageRow>(
      `
        select
          ${packageProjection},
          (
            select branch.name
            from app.branches branch
            where branch.id = app.subscription_packages.branch_id
          ) as branch_name
        from app.subscription_packages
        where (
          $1::boolean
          or (deleted_at is null and is_active)
        )
          and ($2::text is null or name ilike $2)
        order by
          (deleted_at is not null) asc,
          is_active desc,
          sort_order asc,
          lower(name) asc,
          id asc
        limit $3
      `,
      [
        input.includeArchived,
        input.query ? `%${input.query}%` : null,
        input.limit,
      ],
    );
    return result.rows;
  }

  async findForUpdate(
    client: PoolClient,
    packageId: string,
  ): Promise<SubscriptionPackageRow | null> {
    const result = await client.query<SubscriptionPackageRow>(
      `
        select ${packageProjection}
        from app.subscription_packages
        where id = $1
        for update
      `,
      [packageId],
    );
    return result.rows[0] ?? null;
  }

  async create(
    client: PoolClient,
    packageId: string,
    version: number,
    input: SubscriptionPackageValues,
  ): Promise<SubscriptionPackageRow> {
    const result = await client.query<SubscriptionPackageRow>(
      `
        insert into app.subscription_packages (
          id,
          name,
          discipline_id,
          branch_id,
          lessons_total,
          base_price_minor,
          currency_code,
          validity_days,
          is_active,
          sort_order,
          version
        )
        values ($1, $2, $3, $4, $5, $6::bigint, $7, $8, true, $9, $10)
        returning ${packageProjection}
      `,
      [
        packageId,
        input.name,
        input.disciplineId,
        input.branchId,
        input.lessonsTotal,
        input.basePriceMinor,
        input.currencyCode,
        input.validityDays,
        input.sortOrder,
        version,
      ],
    );
    const row = result.rows[0]!;
    await this.recordVersion(client, row);
    return row;
  }

  async update(
    client: PoolClient,
    packageId: string,
    expectedVersion: number,
    nextVersion: number,
    input: SubscriptionPackageValues,
  ): Promise<SubscriptionPackageRow | null> {
    const result = await client.query<SubscriptionPackageRow>(
      `
        update app.subscription_packages
        set name = $3,
          discipline_id = $4,
          branch_id = $5,
          lessons_total = $6,
          base_price_minor = $7::bigint,
          currency_code = $8,
          validity_days = $9,
          sort_order = $10,
          version = $11,
          updated_at = now()
        where id = $1
          and version = $2
          and deleted_at is null
        returning ${packageProjection}
      `,
      [
        packageId,
        expectedVersion,
        input.name,
        input.disciplineId,
        input.branchId,
        input.lessonsTotal,
        input.basePriceMinor,
        input.currencyCode,
        input.validityDays,
        input.sortOrder,
        nextVersion,
      ],
    );
    const row = result.rows[0] ?? null;
    if (row) await this.recordVersion(client, row);
    return row;
  }

  async archive(
    client: PoolClient,
    packageId: string,
    expectedVersion: number,
    nextVersion: number,
  ): Promise<SubscriptionPackageRow | null> {
    const result = await client.query<SubscriptionPackageRow>(
      `
        update app.subscription_packages
        set is_active = false,
          deleted_at = now(),
          version = $3,
          updated_at = now()
        where id = $1
          and version = $2
          and deleted_at is null
        returning ${packageProjection}
      `,
      [packageId, expectedVersion, nextVersion],
    );
    const row = result.rows[0] ?? null;
    if (row) await this.recordVersion(client, row);
    return row;
  }

  async restore(
    client: PoolClient,
    packageId: string,
    expectedVersion: number,
    nextVersion: number,
  ): Promise<SubscriptionPackageRow | null> {
    const result = await client.query<SubscriptionPackageRow>(
      `
        update app.subscription_packages
        set is_active = true,
          deleted_at = null,
          version = $3,
          updated_at = now()
        where id = $1
          and version = $2
          and (deleted_at is not null or not is_active)
        returning ${packageProjection}
      `,
      [packageId, expectedVersion, nextVersion],
    );
    const row = result.rows[0] ?? null;
    if (row) await this.recordVersion(client, row);
    return row;
  }

  private async recordVersion(
    client: PoolClient,
    row: SubscriptionPackageRow,
  ): Promise<void> {
    await client.query(
      `
        insert into app.subscription_package_versions (
          package_id,
          version,
          name,
          discipline_id,
          branch_id,
          unit_count,
          price,
          base_price_minor,
          currency_code,
          validity_days,
          is_active,
          sort_order,
          package_created_at,
          package_updated_at,
          archived_at
        )
        values (
          $1, $2, $3, $4, $5, $6, $7, $8::bigint, $9, $10, $11, $12,
          $13, $14, $15
        )
      `,
      [
        row.id,
        row.version,
        row.name,
        row.discipline_id,
        row.branch_id,
        row.lessons_total,
        row.price,
        row.base_price_minor,
        row.currency_code,
        row.validity_days,
        row.is_active && row.deleted_at === null,
        row.sort_order,
        row.created_at,
        row.updated_at,
        row.deleted_at,
      ],
    );
  }
}
