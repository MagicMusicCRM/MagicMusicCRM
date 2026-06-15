export type NotificationChannel = 'in_app' | 'email' | 'push';
export type NotificationDeliveryStatus = 'queued' | 'sent' | 'failed' | 'skipped';

export interface EmailMessage {
  to: string;
  subject: string;
  text: string;
  html?: string;
}

export interface PushMessage {
  token: string;
  title: string;
  body: string;
  data?: Record<string, unknown>;
}

export interface ProviderResult {
  status: Extract<NotificationDeliveryStatus, 'sent' | 'failed' | 'skipped'>;
  provider: string;
  error?: string;
}
