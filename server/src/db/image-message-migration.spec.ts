import * as fs from 'node:fs';
import * as path from 'node:path';

describe('0074 image message type migration', () => {
  const migrationsDir = path.resolve(process.cwd(), 'db/migrations');

  it('adds image to the message type constraint', () => {
    const sql = fs.readFileSync(
      path.join(migrationsDir, '0074_image_message_type.up.sql'),
      'utf8',
    );

    expect(sql).toContain("'text', 'file', 'image', 'voice', 'system'");
    expect(sql).toContain('messages_message_type_check');
  });

  it('maps images back to files before restoring the old constraint', () => {
    const sql = fs.readFileSync(
      path.join(migrationsDir, '0074_image_message_type.down.sql'),
      'utf8',
    );

    expect(sql).toContain("set message_type = 'file'");
    expect(sql).toContain("where message_type = 'image'");
  });
});
