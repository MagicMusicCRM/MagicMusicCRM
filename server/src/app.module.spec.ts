import { Test } from '@nestjs/testing';
import { DatabaseService } from './db/database.service';
import { NotificationWorker } from './notifications/notification-worker.service';
import { NotificationsService } from './notifications/notifications.service';

describe('AppModule', () => {
  it('compiles the production module graph', async () => {
    process.env.DATABASE_URL = 'postgresql://user:pass@localhost:5432/magiccrm';
    process.env.JWT_ACCESS_SECRET = 'test-secret-test-secret-test-secret-123';
    const { AppModule } = await import('./app.module');
    const moduleRef = await Test.createTestingModule({
      imports: [AppModule]
    })
      .overrideProvider(DatabaseService)
      .useValue({
        query: jest.fn(),
        transaction: jest.fn(),
        onModuleDestroy: jest.fn()
      })
      .compile();

    expect(moduleRef.get(NotificationsService, { strict: false })).toBeDefined();
    expect(moduleRef.get(NotificationWorker, { strict: false })).toBeDefined();

    await moduleRef.close();
  });
});
