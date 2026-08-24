import { Test } from '@nestjs/testing';
import { DatabaseService } from '../db/database.service';
import { MessengerPolicyModule } from './messenger-policy.module';
import { MessengerPolicy } from './messenger.policy';

describe('MessengerPolicyModule', () => {
  it('provides the messenger policy without the full messenger runtime', async () => {
    const moduleRef = await Test.createTestingModule({
      imports: [MessengerPolicyModule]
    })
      .overrideProvider(DatabaseService)
      .useValue({ query: jest.fn() })
      .compile();

    expect(moduleRef.get(MessengerPolicy)).toBeInstanceOf(MessengerPolicy);

    await moduleRef.close();
  });
});
