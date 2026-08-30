export interface AuditPresentationChange {
  key: string;
  label: string;
  before: string | null;
  after: string | null;
}

export interface AuditPresentationEvent {
  id: string;
  actionKey: string;
  title: string;
  summary: string | null;
  reason: string | null;
  actor: { id: string | null; name: string; role: string | null };
  target: {
    type: string;
    id: string | null;
    label: string;
    displayName: string | null;
    routeType: string | null;
  };
  changes: AuditPresentationChange[];
  occurredAt: Date | string;
}

export interface AuditPresentationInput {
  id: string;
  actionKey: string;
  actor: { id: string | null; name: string; role: string | null };
  target: { type: string; id: string | null; displayName: string | null };
  metadata: Record<string, unknown> | null;
  beforeRef: Record<string, unknown> | null;
  afterRef: Record<string, unknown> | null;
  reason: string | null;
  reasonText: string | null;
  occurredAt: Date | string;
}
