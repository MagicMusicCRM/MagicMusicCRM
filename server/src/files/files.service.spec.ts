import { NotFoundException } from '@nestjs/common';
import { Readable } from 'node:stream';
import { AuditService } from '../audit/audit.service';
import { DatabaseService } from '../db/database.service';
import { FileValidator } from './file-validator.service';
import { FilesPolicy } from './files.policy';
import { FilesService } from './files.service';
import { LocalStorageDriver } from './local-storage.driver';

const tokenRow = {
  file_id: 'file-1',
  storage_key: 'private/2026/06/file-1/key.m4a',
  original_name: 'voice.m4a',
  mime_type: 'audio/mp4',
  size_bytes: '10',
  purpose: 'chat_voice'
};

function build(queryImpl: jest.Mock) {
  const database = { query: queryImpl } as unknown as DatabaseService;
  const storage = {
    createReadStream: jest.fn(() => Readable.from([Buffer.from('0123456789')]))
  } as unknown as LocalStorageDriver;
  const service = new FilesService(
    database,
    { record: jest.fn() } as unknown as AuditService,
    {} as FileValidator,
    {} as FilesPolicy,
    storage
  );
  return { service, database, storage };
}

describe('FilesService.downloadByToken', () => {
  it('rejects invalid or expired download tokens', async () => {
    const query = jest.fn(async () => ({ rows: [] }));
    const { service } = build(query);
    await expect(service.downloadByToken('expired-token')).rejects.toThrow(NotFoundException);
  });

  it('allows the same token to be downloaded more than once within its TTL', async () => {
    const query = jest.fn(async (sql: string) =>
      /select/i.test(sql) ? { rows: [tokenRow] } : { rows: [] }
    );
    const { service, storage } = build(query);

    const first = await service.downloadByToken('valid-token');
    const second = await service.downloadByToken('valid-token');

    expect(first.isPartial).toBe(false);
    expect(first.totalSize).toBe(10);
    expect(second.totalSize).toBe(10);
    expect(storage.createReadStream).toHaveBeenCalledTimes(2);
  });

  it('serves a partial range when a Range header is supplied', async () => {
    const query = jest.fn(async (sql: string) =>
      /select/i.test(sql) ? { rows: [tokenRow] } : { rows: [] }
    );
    const { service, storage } = build(query);

    const result = await service.downloadByToken('valid-token', 'bytes=0-3');

    expect(result.isPartial).toBe(true);
    expect(result.start).toBe(0);
    expect(result.end).toBe(3);
    expect(storage.createReadStream).toHaveBeenCalledWith(tokenRow.storage_key, {
      start: 0,
      end: 3
    });
  });
});
