import { Injectable, Logger } from '@nestjs/common';
import type { Server } from 'socket.io';

export type CrmEntity =
  | 'lesson'
  | 'lead'
  | 'student'
  | 'payment'
  | 'subscription'
  | 'group'
  | 'task'
  | 'comment'
  | 'expense'
  | 'user'
  | 'setting'
  | 'notification'
  | 'homework'
  | 'chat_work';

export interface CrmChangedPayload {
  entity: CrmEntity;
  action: 'created' | 'updated' | 'deleted' | 'moved';
  id?: string | null;
  branchId?: string | null;
  /** Optional recipient scoping; used to fan a hint to specific user rooms too. */
  affectedUserIds?: string[] | null;
}

/**
 * Decouples CRM mutation code from the WebSocket gateway. MessengerModule already
 * imports CrmModule, so injecting the gateway into CrmService directly would be a
 * circular dependency. Instead this bus is provided by a @Global module; the
 * gateway registers its Socket.IO server here on init, and CRM services publish
 * lightweight "something changed" hints that staff clients use to refetch.
 */
@Injectable()
export class RealtimeBus {
  static readonly crmRoom = 'crm';

  private readonly logger = new Logger(RealtimeBus.name);
  private server?: Server;

  setServer(server: Server): void {
    this.server = server;
  }

  /**
   * Broadcast a CRM invalidation hint to every staff socket in the shared CRM
   * room. The payload carries no PII — clients refetch through the authorized
   * REST API. Never throws (realtime is best-effort, must not break a write).
   */
  emitCrmChanged(payload: CrmChangedPayload): void {
    try {
      this.server?.to(RealtimeBus.crmRoom).emit('crm.changed', payload);
      // Recipient-scoped fan-out: lets non-staff (e.g. a client receiving a new
      // in-app notification) get the same invalidation hint in their user room.
      const userIds = payload.affectedUserIds ?? [];
      for (const userId of userIds) {
        if (userId) this.server?.to(`user:${userId}`).emit('crm.changed', payload);
      }
    } catch (err) {
      this.logger.warn(`Failed to emit crm.changed: ${String(err)}`);
    }
  }

  /**
   * Broadcast a shared-setting change to every authenticated socket. Used for
   * settings that affect UI visible to ALL roles (e.g. the administration chat
   * avatar). RBAC-safe: the payload carries only the setting key — clients
   * refetch the value through the authorized REST endpoint.
   */
  emitSettingChanged(key: string): void {
    try {
      this.server?.emit('crm.changed', {
        entity: 'setting',
        action: 'updated',
        id: key,
      } satisfies CrmChangedPayload);
    } catch (err) {
      this.logger.warn(`Failed to emit setting change: ${String(err)}`);
    }
  }
}
