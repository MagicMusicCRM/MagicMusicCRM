import { Injectable, Logger } from '@nestjs/common';
import type { Server } from 'socket.io';

export type CrmEntity =
  | 'lesson'
  | 'lead'
  | 'student'
  | 'payment'
  | 'task'
  | 'comment';

export interface CrmChangedPayload {
  entity: CrmEntity;
  action: 'created' | 'updated' | 'deleted';
  id?: string | null;
  branchId?: string | null;
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
    } catch (err) {
      this.logger.warn(`Failed to emit crm.changed: ${String(err)}`);
    }
  }
}
