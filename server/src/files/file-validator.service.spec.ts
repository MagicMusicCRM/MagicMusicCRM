import { BadRequestException } from '@nestjs/common';
import { FileValidator } from './file-validator.service';
import { UploadedMemoryFile } from './file-upload.types';

describe('FileValidator', () => {
  const validator = new FileValidator();

  function file(overrides: Partial<UploadedMemoryFile> = {}): UploadedMemoryFile {
    return {
      originalname: 'avatar.png',
      mimetype: 'image/png',
      size: 128,
      buffer: Buffer.from('file'),
      ...overrides
    };
  }

  it('rejects oversized files for purpose', () => {
    expect(() =>
      validator.validate(file({ size: 1024 * 1024 + 1 }), 'profile_avatar')
    ).toThrow(BadRequestException);
  });

  it('rejects disallowed MIME types', () => {
    expect(() =>
      validator.validate(file({ mimetype: 'application/x-msdownload' }), 'chat_attachment')
    ).toThrow(BadRequestException);
  });

  it('normalizes path traversal names for display only and derives extension from MIME', () => {
    const result = validator.validate(
      file({ originalname: '..\\..\\secret.php.jpg', mimetype: 'image/jpeg' }),
      'profile_avatar'
    );

    expect(result.originalName).toBe('secret.php.jpg');
    expect(result.extension).toBe('jpg');
  });

  it('accepts a homework attachment at the 25MB limit (P5c)', () => {
    const result = validator.validate(
      file({
        originalname: 'homework.pdf',
        mimetype: 'application/pdf',
        size: 25 * 1024 * 1024
      }),
      'homework_attachment'
    );

    expect(result.mimeType).toBe('application/pdf');
    expect(result.extension).toBe('pdf');
  });

  it('rejects an oversized homework attachment (P5c)', () => {
    expect(() =>
      validator.validate(
        file({ mimetype: 'application/pdf', size: 25 * 1024 * 1024 + 1 }),
        'homework_attachment'
      )
    ).toThrow(BadRequestException);
  });
});
