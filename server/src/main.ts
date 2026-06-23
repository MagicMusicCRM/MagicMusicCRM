import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { SafeExceptionFilter } from './common/filters/safe-exception.filter';
import { SafeLogger } from './common/logging/safe-logger.service';

async function bootstrap() {
  const app = await NestFactory.create(AppModule, { bufferLogs: true });
  const logger = app.get(SafeLogger);
  const config = app.get(ConfigService);

  app.useLogger(logger);
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true
    })
  );
  app.useGlobalFilters(new SafeExceptionFilter(logger));
  app.enableShutdownHooks();
  app.getHttpAdapter().getInstance().disable('x-powered-by');
  // За единственным reverse-proxy (Caddy): доверяем 1 hop, чтобы req.ip
  // отражал реальный IP клиента (нужно для IP-троттлинга сброса пароля и т.п.).
  app.getHttpAdapter().getInstance().set('trust proxy', 1);
  app.setGlobalPrefix('api');

  const allowedOrigins = config.get<string>('CORS_ALLOWED_ORIGINS', '');
  const origin = allowedOrigins
    .split(',')
    .map((value) => value.trim())
    .filter(Boolean);

  app.enableCors({
    origin: origin.length > 0 ? origin : false,
    credentials: true
  });

  const port = config.get<number>('PORT', 3000);
  await app.listen(port, '0.0.0.0');
  logger.log(`MagicMusicCRM API listening on port ${port}`, 'Bootstrap');
}

void bootstrap();
