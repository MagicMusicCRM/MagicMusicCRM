import { Injectable, NotFoundException, StreamableFile } from "@nestjs/common";
import { createHash, randomBytes, randomUUID } from "node:crypto";
import { basename } from "node:path";
import { AuditService } from "../audit/audit.service";
import { ActorContext } from "../common/security/actor-context";
import { DatabaseService } from "../db/database.service";
import { UploadFileDto } from "./dto/upload-file.dto";
import { FileValidator } from "./file-validator.service";
import { UploadedMemoryFile } from "./file-upload.types";
import { FileAccessRecord, FilesPolicy } from "./files.policy";
import { LocalStorageDriver } from "./local-storage.driver";

interface FileRow extends FileAccessRecord {
  original_name: string;
  mime_type: string;
  size_bytes: string;
  storage_key: string;
  sha256: string;
  created_by: string | null;
  created_at: Date | string;
}

interface TokenRow {
  file_id: string;
  storage_key: string;
  original_name: string;
  mime_type: string;
  size_bytes: string;
  purpose: string;
}

@Injectable()
export class FilesService {
  constructor(
    private readonly database: DatabaseService,
    private readonly audit: AuditService,
    private readonly validator: FileValidator,
    private readonly policy: FilesPolicy,
    private readonly storage: LocalStorageDriver,
  ) {}

  async upload(
    actor: ActorContext,
    dto: UploadFileDto,
    file: UploadedMemoryFile | undefined,
  ) {
    const validated = this.validator.validate(file, dto.purpose);
    const ownerUserId = await this.policy.assertCanUpload(
      actor,
      dto.purpose,
      dto.ownerType,
      dto.ownerId,
    );
    const id = randomUUID();
    const storageKey = this.createStorageKey(id, validated.extension);
    const sha256 = this.sha256(file!.buffer);

    await this.storage.write(storageKey, file!.buffer);
    try {
      const result = await this.database.query<FileRow>(
        `
          insert into app.file_objects (
            id, owner_user_id, owner_type, owner_id, purpose, original_name,
            mime_type, size_bytes, storage_key, sha256, created_by
          )
          values ($1, $2, $3, $4, $5::app.file_purpose, $6, $7, $8, $9, $10, $11)
          returning id, owner_user_id, owner_type, owner_id, purpose, original_name,
            mime_type, size_bytes, storage_key, sha256, created_by, created_at, deleted_at
        `,
        [
          id,
          ownerUserId,
          dto.ownerType ?? null,
          dto.ownerId ?? null,
          dto.purpose,
          validated.originalName,
          validated.mimeType,
          validated.sizeBytes,
          storageKey,
          sha256,
          actor.userId,
        ],
      );

      await this.audit.record({
        actor,
        action: "files.uploaded",
        entityType: "file",
        entityId: id,
        metadata: { purpose: dto.purpose, sizeBytes: validated.sizeBytes },
      });
      return this.toDto(result.rows[0]);
    } catch (error) {
      await this.storage.delete(storageKey);
      throw error;
    }
  }

  async getMetadata(actor: ActorContext, fileId: string) {
    const file = await this.requireFile(fileId);
    await this.policy.assertCanRead(actor, file);
    return this.toDto(file);
  }

  async issueDownloadToken(actor: ActorContext, fileId: string) {
    const file = await this.requireFile(fileId);
    await this.policy.assertCanRead(actor, file);
    const token = randomBytes(32).toString("base64url");
    const expiresAt = new Date(Date.now() + this.ttlMs(file.purpose));
    await this.database.query(
      `
        insert into app.file_download_tokens (
          token_hash, file_id, actor_user_id, expires_at
        )
        values ($1, $2, $3, $4)
      `,
      [this.tokenHash(token), fileId, actor.userId, expiresAt],
    );
    await this.audit.record({
      actor,
      action: "files.download_token_issued",
      entityType: "file",
      entityId: fileId,
    });
    return { token, expiresAt };
  }

  async downloadByToken(
    token: string,
  ): Promise<{
    stream: StreamableFile;
    fileName: string;
    mimeType: string;
    sizeBytes: number;
  }> {
    const result = await this.database.transaction(async (client) => {
      const selected = await client.query<TokenRow>(
        `
          select f.id as file_id, f.storage_key, f.original_name, f.mime_type,
            f.size_bytes, f.purpose
          from app.file_download_tokens t
          join app.file_objects f on f.id = t.file_id
          where t.token_hash = $1
            and t.expires_at > now()
            and t.used_at is null
            and f.deleted_at is null
          limit 1
          for update of t
        `,
        [this.tokenHash(token)],
      );
      const row = selected.rows[0];
      if (!row)
        throw new NotFoundException("Ссылка недействительна или истекла.");
      await client.query(
        "update app.file_download_tokens set used_at = now() where token_hash = $1",
        [this.tokenHash(token)],
      );
      return row;
    });

    return {
      stream: new StreamableFile(
        this.storage.createReadStream(result.storage_key),
      ),
      fileName: basename(result.original_name),
      mimeType: result.mime_type,
      sizeBytes: Number(result.size_bytes),
    };
  }

  async delete(actor: ActorContext, fileId: string) {
    const file = await this.requireFile(fileId);
    this.policy.assertCanDelete(actor, file);
    const result = await this.database.query<FileRow>(
      `
        update app.file_objects
        set deleted_at = now()
        where id = $1 and deleted_at is null
        returning id, owner_user_id, owner_type, owner_id, purpose, original_name,
          mime_type, size_bytes, storage_key, sha256, created_by, created_at, deleted_at
      `,
      [fileId],
    );
    await this.audit.record({
      actor,
      action: "files.deleted",
      entityType: "file",
      entityId: fileId,
    });
    return this.toDto(result.rows[0]);
  }

  private async requireFile(fileId: string): Promise<FileRow> {
    const result = await this.database.query<FileRow>(
      `
        select id, owner_user_id, owner_type, owner_id, purpose, original_name,
          mime_type, size_bytes, storage_key, sha256, created_by, created_at, deleted_at
        from app.file_objects
        where id = $1
        limit 1
      `,
      [fileId],
    );
    const file = result.rows[0];
    if (!file || file.deleted_at)
      throw new NotFoundException("Файл не найден.");
    return file;
  }

  private createStorageKey(fileId: string, extension: string): string {
    const now = new Date();
    const yyyy = String(now.getUTCFullYear());
    const mm = String(now.getUTCMonth() + 1).padStart(2, "0");
    return `private/${yyyy}/${mm}/${fileId}/${randomBytes(32).toString("hex")}.${extension}`;
  }

  private sha256(buffer: Buffer): string {
    return createHash("sha256").update(buffer).digest("hex");
  }

  private tokenHash(token: string): string {
    return createHash("sha256").update(token).digest("hex");
  }

  private ttlMs(purpose: string): number {
    return purpose === "crm_document" ? 60_000 : 5 * 60_000;
  }

  private toDto(row: FileRow) {
    return {
      id: row.id,
      ownerUserId: row.owner_user_id,
      ownerType: row.owner_type,
      ownerId: row.owner_id,
      purpose: row.purpose,
      originalName: row.original_name,
      mimeType: row.mime_type,
      sizeBytes: Number(row.size_bytes),
      sha256: row.sha256,
      createdBy: row.created_by,
      createdAt: row.created_at,
      deletedAt: row.deleted_at,
    };
  }
}
