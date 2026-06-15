export type LegalDocumentType = 'privacy_policy' | 'terms_of_use' | 'account_deletion';

export type AccountDeletionStatus =
  | 'pending'
  | 'processing'
  | 'completed'
  | 'rejected'
  | 'cancelled';

export interface ConsentEvidence {
  ip?: string;
  userAgent?: string;
}
