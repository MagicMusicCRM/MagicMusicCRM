import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { JWT } from 'google-auth-library';
import { ProviderResult, PushMessage } from './notifications.types';

@Injectable()
export class FirebasePushProvider {
  constructor(private readonly config: ConfigService) {}

  async send(message: PushMessage): Promise<ProviderResult> {
    const projectId = this.config.get<string>('FIREBASE_PROJECT_ID', '');
    const clientEmail = this.config.get<string>('FIREBASE_CLIENT_EMAIL', '');
    const privateKey = this.config.get<string>('FIREBASE_PRIVATE_KEY', '').replace(/\\n/g, '\n');
    if (!projectId || !clientEmail || !privateKey) {
      return { provider: 'firebase', status: 'skipped', error: 'not_configured' };
    }

    const timeoutMs = this.config.get<number>('FIREBASE_TIMEOUT_MS', 5000);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const accessToken = await this.accessToken(clientEmail, privateKey);
      if (!accessToken) {
        return { provider: 'firebase', status: 'failed', error: 'auth_failed' };
      }

      const response = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: 'POST',
          headers: {
            authorization: `Bearer ${accessToken}`,
            'content-type': 'application/json'
          },
          body: JSON.stringify({
            message: {
              token: message.token,
              notification: {
                title: message.title,
                body: message.body
              },
              data: this.stringifyData(message.data),
              android: {
                priority: 'HIGH'
              },
              apns: {
                payload: {
                  aps: {
                    sound: 'default'
                  }
                }
              }
            }
          }),
          signal: controller.signal
        }
      );

      if (response.ok) return { provider: 'firebase', status: 'sent' };
      return { provider: 'firebase', status: 'failed', error: `status_${response.status}` };
    } catch (error) {
      if (controller.signal.aborted || (error instanceof Error && error.name === 'AbortError')) {
        return { provider: 'firebase', status: 'failed', error: 'timeout' };
      }
      return { provider: 'firebase', status: 'failed', error: 'provider_error' };
    } finally {
      clearTimeout(timeout);
    }
  }

  private async accessToken(clientEmail: string, privateKey: string): Promise<string | null> {
    const client = new JWT({
      email: clientEmail,
      key: privateKey,
      scopes: ['https://www.googleapis.com/auth/firebase.messaging']
    });
    const token = await client.getAccessToken();
    return typeof token === 'string' ? token : token.token ?? null;
  }

  private stringifyData(data: Record<string, unknown> = {}): Record<string, string> {
    return Object.fromEntries(
      Object.entries(data)
        .filter(([, value]) => value !== null && value !== undefined && typeof value !== 'object')
        .map(([key, value]) => [key, String(value).slice(0, 256)])
    );
  }
}
