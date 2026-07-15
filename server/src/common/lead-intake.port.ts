import { ActorContext } from "./security/actor-context";

/**
 * Narrow port the messenger needs from the CRM: promote a chat sender into a
 * lead. Messenger depends on this one-method contract instead of the whole
 * CrmService, so the two modules can split independently (B2). CrmModule binds
 * the token to its current implementation; when the lead logic moves to a
 * dedicated service (B5) only that binding changes.
 */
export const LEAD_INTAKE_PORT = Symbol("LEAD_INTAKE_PORT");

export interface LeadIntakePort {
  autoCreateLeadFromChat(
    actor: ActorContext,
    senderUserId: string,
  ): Promise<{ leadId: string | null; created: boolean }>;
}
