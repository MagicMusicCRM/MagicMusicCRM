import * as fs from "node:fs";
import * as path from "node:path";

describe("0125 messenger media integrity migration", () => {
  const migrationsDir = path.resolve(process.cwd(), "db/migrations");

  it("persists bounded voice duration and protects attachment references", () => {
    const sql = fs.readFileSync(
      path.join(migrationsDir, "0125_messenger_media_integrity.up.sql"),
      "utf8",
    );

    expect(sql).toContain("voice_duration_ms integer");
    expect(sql).toContain("messages_attachment_file_fk");
    expect(sql).toMatch(
      /references app\.file_objects\(id\)\s+on delete set null/,
    );
    expect(sql).toContain("voice_duration_ms between 1 and 3600000");
    expect(sql).toContain("drop constraint if exists message_payload_check");
    expect(sql).toMatch(
      /message_payload_check[\s\S]*deleted_at is not null[\s\S]*attachment_file_id is not null/,
    );
    expect(sql).toContain("not valid");
  });

  it("reverses every added schema object", () => {
    const sql = fs.readFileSync(
      path.join(migrationsDir, "0125_messenger_media_integrity.down.sql"),
      "utf8",
    );

    expect(sql).toContain(
      "drop constraint if exists messages_voice_duration_check",
    );
    expect(sql).toContain(
      "drop constraint if exists messages_attachment_file_fk",
    );
    expect(sql).toContain("drop column if exists voice_duration_ms");
    expect(sql).toMatch(
      /message_payload_check[\s\S]*content is not null[\s\S]*attachment_file_id is not null/,
    );
  });
});
