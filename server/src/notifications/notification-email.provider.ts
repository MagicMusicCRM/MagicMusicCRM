import { Injectable } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Socket } from 'node:net';
import { connect as tlsConnect, TLSSocket } from 'node:tls';
import { EmailMessage, ProviderResult } from './notifications.types';

@Injectable()
export class ResendEmailProvider {
  constructor(private readonly config: ConfigService) {}

  async send(message: EmailMessage): Promise<ProviderResult> {
    const apiKey = this.config.get<string>('RESEND_API_KEY', '');
    const from = this.config.get<string>('RESEND_FROM_EMAIL', '');
    if (!apiKey || !from) return { provider: 'resend', status: 'skipped', error: 'not_configured' };

    const timeoutMs = this.config.get<number>('RESEND_TIMEOUT_MS', 5000);
    const controller = new AbortController();
    const timeout = setTimeout(() => controller.abort(), timeoutMs);
    try {
      const response = await fetch('https://api.resend.com/emails', {
        method: 'POST',
        headers: {
          authorization: `Bearer ${apiKey}`,
          'content-type': 'application/json'
        },
        body: JSON.stringify({
          from,
          to: [message.to],
          subject: message.subject,
          text: message.text,
          html: message.html
        }),
        signal: controller.signal
      });

      if (response.ok) return { provider: 'resend', status: 'sent' };
      return { provider: 'resend', status: 'failed', error: `status_${response.status}` };
    } catch (error) {
      if (controller.signal.aborted || (error instanceof Error && error.name === 'AbortError')) {
        return { provider: 'resend', status: 'failed', error: 'timeout' };
      }
      return { provider: 'resend', status: 'failed', error: 'provider_error' };
    } finally {
      clearTimeout(timeout);
    }
  }
}

@Injectable()
export class SmtpFallbackEmailProvider {
  constructor(private readonly config: ConfigService) {}

  async send(message: EmailMessage): Promise<ProviderResult> {
    const host = this.config.get<string>('SMTP_FALLBACK_HOST', '');
    const port = this.config.get<number>('SMTP_FALLBACK_PORT', 465);
    const secure = this.config.get<boolean>('SMTP_FALLBACK_SECURE', true);
    const from =
      this.config.get<string>('SMTP_FALLBACK_FROM_EMAIL', '') ||
      this.config.get<string>('RESEND_FROM_EMAIL', '');
    if (!host || !from) return { provider: 'smtp_fallback', status: 'skipped', error: 'not_configured' };

    try {
      await this.sendSmtp({ host, port, secure, from, message });
      return { provider: 'smtp_fallback', status: 'sent' };
    } catch (error) {
      return {
        provider: 'smtp_fallback',
        status: 'failed',
        error: error instanceof Error ? error.message.slice(0, 160) : 'smtp_failed'
      };
    }
  }

  private async sendSmtp(input: {
    host: string;
    port: number;
    secure: boolean;
    from: string;
    message: EmailMessage;
  }): Promise<void> {
    const socket = await this.connect(input.host, input.port, input.secure);
    try {
      await this.read(socket);
      await this.command(socket, `EHLO magic-music.org\r\n`);
      const user = this.config.get<string>('SMTP_FALLBACK_USER', '');
      const password = this.config.get<string>('SMTP_FALLBACK_PASSWORD', '');
      if (user && password) {
        const auth = Buffer.from(`\u0000${user}\u0000${password}`).toString('base64');
        await this.command(socket, `AUTH PLAIN ${auth}\r\n`, [235]);
      }
      await this.command(socket, `MAIL FROM:<${input.from}>\r\n`);
      await this.command(socket, `RCPT TO:<${input.message.to}>\r\n`);
      await this.command(socket, 'DATA\r\n', [354]);
      await this.command(
        socket,
        this.composeMimeMessage(input.from, input.message)
      );
      await this.command(socket, 'QUIT\r\n', [221]);
    } finally {
      socket.end();
    }
  }

  private composeMimeMessage(from: string, message: EmailMessage): string {
    const headers = [
      `From: ${from}`,
      `To: ${message.to}`,
      `Subject: ${message.subject.replace(/\r|\n/g, ' ')}`,
      'MIME-Version: 1.0'
    ];
    if (!message.html) {
      return [
        ...headers,
        'Content-Type: text/plain; charset=utf-8',
        '',
        this.escapeSmtpData(message.text),
        '.',
        ''
      ].join('\r\n');
    }

    const boundary = `magicmusic-${Date.now().toString(36)}`;
    return [
      ...headers,
      `Content-Type: multipart/alternative; boundary="${boundary}"`,
      '',
      `--${boundary}`,
      'Content-Type: text/plain; charset=utf-8',
      '',
      this.escapeSmtpData(message.text),
      `--${boundary}`,
      'Content-Type: text/html; charset=utf-8',
      '',
      this.escapeSmtpData(message.html),
      `--${boundary}--`,
      '.',
      ''
    ].join('\r\n');
  }

  private escapeSmtpData(value: string): string {
    return value.replace(/\r?\n\./g, '\n..');
  }

  private connect(host: string, port: number, secure: boolean): Promise<Socket | TLSSocket> {
    return new Promise((resolve, reject) => {
      const socket = secure ? tlsConnect({ host, port }) : new Socket().connect(port, host);
      socket.setTimeout(10_000);
      if (secure) {
        socket.once('secureConnect', () => resolve(socket));
      } else {
        socket.once('connect', () => resolve(socket));
      }
      socket.once('timeout', () => reject(new Error('smtp_timeout')));
      socket.once('error', reject);
    });
  }

  private async command(socket: Socket | TLSSocket, command: string, ok = [250]): Promise<string> {
    socket.write(command);
    const response = await this.read(socket);
    const code = Number(response.slice(0, 3));
    if (!ok.includes(code)) throw new Error(`smtp_status_${code || 'unknown'}`);
    return response;
  }

  private read(socket: Socket | TLSSocket): Promise<string> {
    return new Promise((resolve, reject) => {
      let buffer = '';
      const onData = (chunk: Buffer) => {
        buffer += chunk.toString('utf8');
        const lines = buffer.split(/\r?\n/).filter(Boolean);
        const last = lines[lines.length - 1];
        if (last && /^\d{3} /.test(last)) {
          cleanup();
          resolve(buffer);
        }
      };
      const onError = (error: Error) => {
        cleanup();
        reject(error);
      };
      const cleanup = () => {
        socket.off('data', onData);
        socket.off('error', onError);
      };
      socket.on('data', onData);
      socket.on('error', onError);
    });
  }
}
