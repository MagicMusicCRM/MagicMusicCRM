import { ForbiddenException } from '@nestjs/common';
import { DatabaseService } from './database.service';
import { ActorContext } from '../common/security/actor-context';
import { ScopedRepository } from './scoped-repository';

class TestRepository extends ScopedRepository {
  constructor() {
    super({} as DatabaseService);
  }

  check(actor: ActorContext, ownerId: string) {
    this.assertSelfOrStaff(actor, ownerId);
  }
}

describe('ScopedRepository', () => {
  const repository = new TestRepository();

  it('allows owner access', () => {
    expect(() =>
      repository.check({ userId: 'user-a', role: 'client' }, 'user-a')
    ).not.toThrow();
  });

  it('allows staff access', () => {
    expect(() =>
      repository.check({ userId: 'manager-a', role: 'manager' }, 'user-b')
    ).not.toThrow();
  });

  it('denies foreign client access', () => {
    expect(() =>
      repository.check({ userId: 'user-a', role: 'client' }, 'user-b')
    ).toThrow(ForbiddenException);
  });
});
