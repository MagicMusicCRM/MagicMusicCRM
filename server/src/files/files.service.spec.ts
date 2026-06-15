import { NotFoundException } from '@nestjs/common';
import { AuditService } from '../audit/audit.service';
import { DatabaseService } from '../db/database.service';
import { FileValidator } from './file-validator.service';
import { FilesPolicy } from './files.policy';
import { FilesService } from './files.service';
import { LocalStorageDriver } from './local-storage.driver';

describe('FilesService', () => {
  it('rejects invalid or expired download tokens', async () => {
    const database = {
      transaction: jest.fn(async (work: (client: { query: jest.Mock }) => Promise<unknown>) =>
        work({ query: jest.fn().mockResolvedValueOnce({ rows: [] }) })
      )
    } as unknown as DatabaseService;

    const service = new FilesService(
      database,
      { record: jest.fn() } as unknown as AuditService,
      {} as FileValidator,
      {} as FilesPolicy,
      {} as LocalStorageDriver
    );

    await expect(service.downloadByToken('expired-token')).rejects.toThrow(NotFoundException);
  });
});
