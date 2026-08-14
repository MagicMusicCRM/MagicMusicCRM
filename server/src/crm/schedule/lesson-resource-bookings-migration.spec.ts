import { readFile } from "fs/promises";
import { resolve } from "path";

describe("0137 lesson resource bookings migration contract", () => {
  it("preflights existing data and installs exclusion-backed projections", async () => {
    const up = await readFile(
      resolve(
        process.cwd(),
        "db/migrations/0137_lesson_resource_bookings.up.sql",
      ),
      "utf8",
    );
    const down = await readFile(
      resolve(
        process.cwd(),
        "db/migrations/0137_lesson_resource_bookings.down.sql",
      ),
      "utf8",
    );

    expect(up).toMatch(/create extension if not exists btree_gist/i);
    expect(up).toMatch(/create table if not exists app\.lesson_resource_bookings/i);
    expect(up).toMatch(/lesson resource booking preflight failed/i);
    expect(up).toMatch(/exclude using gist/i);
    expect(up).toMatch(/resource_type with =/i);
    expect(up).toMatch(/resource_id with =/i);
    expect(up).toMatch(/occupied_at with &&/i);
    expect(up).toMatch(/lesson_snapshot_participants/i);
    expect(up).toMatch(/group_students/i);
    expect(up).toMatch(/after insert or update of[\s\S]*or delete on app\.lessons/i);
    expect(up).toMatch(
      /after insert or update or delete on app\.lesson_snapshot_participants/i,
    );
    expect(up).toMatch(
      /revoke insert, update, delete on app\.lesson_resource_bookings/i,
    );
    expect(up).toMatch(
      /revoke execute on function app\.refresh_lesson_resource_bookings\(uuid\)/i,
    );
    expect(down).toMatch(/drop table if exists app\.lesson_resource_bookings/i);
  });
});
