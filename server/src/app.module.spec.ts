import { Test } from '@nestjs/testing';
import { DatabaseService } from './db/database.service';

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

    await moduleRef.close();
  });
});
