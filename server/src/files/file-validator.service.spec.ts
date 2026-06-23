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
      buffer: Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
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
      file({
        originalname: '..\\..\\secret.php.jpg',
        mimetype: 'image/jpeg',
        buffer: Buffer.from([0xff, 0xd8, 0xff, 0xe0])
      }),
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
        size: 25 * 1024 * 1024,
        buffer: Buffer.from('%PDF-1.4 homework')
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

  it('rejects content that does not match the declared image MIME (spoofing)', () => {
    expect(() =>
      validator.validate(
        file({
          mimetype: 'image/png',
          buffer: Buffer.from('<html>not really a png</html>')
        }),
        'profile_avatar'
      )
    ).toThrow(BadRequestException);
  });
});
