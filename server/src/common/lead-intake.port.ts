import { ActorContext } from "./security/actor-context";

/**
 * Narrow client-intake port shared by onboarding and messenger. The historical
 * method name remains for compatibility, but the operation is the canonical,
 * idempotent "ensure this app client has a CRM identity" command. CrmModule
 * binds the token to the implementation so consumers do not depend on the
 * whole CRM module surface.
 */
export const LEAD_INTAKE_PORT = Symbol("LEAD_INTAKE_PORT");

export interface LeadIntakePort {
  autoCreateLeadFromChat(
    actor: ActorContext,
    senderUserId: string,
    trigger?: "chat" | "onboarding",
  ): Promise<{ leadId: string | null; created: boolean }>;
}
