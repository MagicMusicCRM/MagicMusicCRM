import { Injectable, NotFoundException } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { createReadStream } from 'node:fs';
import { mkdir, readFile, rm, writeFile } from 'node:fs/promises';
import { dirname, join, resolve } from 'node:path';
import { Readable } from 'node:stream';

@Injectable()
export class LocalStorageDriver {
  private readonly root: string;

  constructor(config: ConfigService) {
    this.root = resolve(config.get<string>('FILE_STORAGE_ROOT', '/opt/magicmusiccrm/storage/private'));
  }

  async write(storageKey: string, buffer: Buffer): Promise<void> {
    const path = this.resolveStoragePath(storageKey);
    await mkdir(dirname(path), { recursive: true });
    await writeFile(path, buffer, { flag: 'wx' });
  }

  createReadStream(storageKey: string): Readable {
    return createReadStream(this.resolveStoragePath(storageKey));
  }

  async read(storageKey: string): Promise<Buffer> {
    try {
      return await readFile(this.resolveStoragePath(storageKey));
    } catch {
      throw new NotFoundException('Файл не найден.');
    }
  }

  async delete(storageKey: string): Promise<void> {
    await rm(this.resolveStoragePath(storageKey), { force: true });
  }

  resolveStoragePath(storageKey: string): string {
    const resolved = resolve(join(this.root, storageKey));
    if (!resolved.startsWith(`${this.root}\\`) && resolved !== this.root && !resolved.startsWith(`${this.root}/`)) {
      throw new NotFoundException('Файл не найден.');
    }
    return resolved;
  }
}
