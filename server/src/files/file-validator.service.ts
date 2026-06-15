import { BadRequestException, Injectable } from '@nestjs/common';
import { FilePurpose } from './dto/upload-file.dto';
import { UploadedMemoryFile } from './file-upload.types';

export interface ValidatedFile {
  originalName: string;
  mimeType: string;
  sizeBytes: number;
  extension: string;
}

interface PurposeRule {
  maxBytes: number;
  mimeToExtension: Record<string, string>;
}

const MB = 1024 * 1024;

const COMMON_ATTACHMENT_MIME: Record<string, string> = {
  'image/png': 'png',
  'image/jpeg': 'jpg',
  'image/webp': 'webp',
  'application/pdf': 'pdf',
  'text/plain': 'txt',
  'application/msword': 'doc',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document': 'docx',
  'application/vnd.ms-excel': 'xls',
  'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet': 'xlsx',
  'audio/mpeg': 'mp3',
  'audio/mp4': 'm4a',
  'audio/ogg': 'ogg',
  'audio/webm': 'webm',
  'audio/wav': 'wav',
  'video/mp4': 'mp4',
  'video/webm': 'webm'
};

const RULES: Record<FilePurpose, PurposeRule> = {
  profile_avatar: {
    maxBytes: MB,
    mimeToExtension: {
      'image/png': 'png',
      'image/jpeg': 'jpg',
      'image/webp': 'webp'
    }
  },
  chat_attachment: {
    maxBytes: 25 * MB,
    mimeToExtension: COMMON_ATTACHMENT_MIME
  },
  chat_voice: {
    maxBytes: 25 * MB,
    mimeToExtension: {
      'audio/mpeg': 'mp3',
      'audio/mp4': 'm4a',
      'audio/ogg': 'ogg',
      'audio/webm': 'webm',
      'audio/wav': 'wav'
    }
  },
  legal_document: {
    maxBytes: 10 * MB,
    mimeToExtension: { 'application/pdf': 'pdf' }
  },
  crm_document: {
    maxBytes: 25 * MB,
    mimeToExtension: COMMON_ATTACHMENT_MIME
  }
};

@Injectable()
export class FileValidator {
  validate(file: UploadedMemoryFile | undefined, purpose: FilePurpose): ValidatedFile {
    if (!file) throw new BadRequestException('Файл обязателен.');
    if (!file.buffer || file.size <= 0) {
      throw new BadRequestException('Файл пустой.');
    }

    const rule = RULES[purpose];
    if (file.size > rule.maxBytes) {
      throw new BadRequestException('Файл превышает допустимый размер.');
    }

    const extension = rule.mimeToExtension[file.mimetype];
    if (!extension) {
      throw new BadRequestException('Тип файла не разрешен.');
    }

    return {
      originalName: this.normalizeOriginalName(file.originalname),
      mimeType: file.mimetype,
      sizeBytes: file.size,
      extension
    };
  }

  private normalizeOriginalName(originalName: string): string {
    const base = originalName
      .replace(/\\/g, '/')
      .split('/')
      .pop()
      ?.trim();
    const safe = (base || 'file')
      .replace(/[\u0000-\u001f]/g, '')
      .replace(/[<>:"|?*]/g, '_')
      .slice(0, 180);
    return safe.length > 0 ? safe : 'file';
  }
}
