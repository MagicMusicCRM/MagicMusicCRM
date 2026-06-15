import { ConsoleLogger, Injectable } from '@nestjs/common';
import { redactSensitive } from './redact.util';

@Injectable()
export class SafeLogger extends ConsoleLogger {
  protected stringifyMessage(message: unknown): string {
    if (typeof message === 'string') return message;

    try {
      return JSON.stringify(redactSensitive(message));
    } catch {
      return '[Unserializable log message]';
    }
  }

  log(message: unknown, context?: string) {
    super.log(this.stringifyMessage(message), context);
  }

  error(message: unknown, stack?: string, context?: string) {
    super.error(this.stringifyMessage(message), stack, context);
  }

  warn(message: unknown, context?: string) {
    super.warn(this.stringifyMessage(message), context);
  }

  debug(message: unknown, context?: string) {
    super.debug?.(this.stringifyMessage(message), context);
  }

  verbose(message: unknown, context?: string) {
    super.verbose?.(this.stringifyMessage(message), context);
  }
}
