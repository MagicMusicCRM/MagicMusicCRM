import type { TypedClientCustomValue } from "../clients/client-config.repository";

export interface PreparedStudentCreate {
  readonly firstName: string;
  readonly lastName: string | null;
  readonly email: string | null;
  readonly fullName: string;
  readonly phone: string | null;
  readonly status: string;
  readonly leadId: string | null;
  readonly customDataPatch: Readonly<Record<string, unknown>>;
  readonly requestedResponsibleId: string | undefined;
  readonly branchId: string | null;
  readonly sourceId: string | null;
  readonly customFields?: ReadonlyArray<TypedClientCustomValue>;
}

export interface PreparedStudentUpdate {
  readonly studentId: string;
  readonly expectedVersion?: number;
  readonly firstName: string | null;
  readonly lastName: string | null;
  readonly phone: string | null;
  readonly email: string | null;
  readonly clearEmail?: boolean;
  readonly status: string | null;
  readonly customDataPatch: Readonly<Record<string, unknown>>;
  readonly requestedResponsibleId: string | undefined;
  readonly branchId: string | null;
  readonly clearResponsible: boolean;
  readonly sourceId: string | null;
  readonly customFields?: ReadonlyArray<TypedClientCustomValue>;
}

export interface StudentWriteSnapshot {
  readonly version: string | number;
  readonly status: string | null;
  readonly branch_id: string | null;
  readonly first_name: string | null;
  readonly last_name: string | null;
  readonly phone: string | null;
  readonly email: string | null;
  readonly custom_data: Record<string, unknown> | null;
}
