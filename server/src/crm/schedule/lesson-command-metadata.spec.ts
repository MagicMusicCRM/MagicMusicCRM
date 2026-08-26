import { readFileSync } from "node:fs";
import { resolve } from "node:path";

const readSource = (name: string) =>
  readFileSync(resolve(__dirname, name), "utf8");

describe("LessonCommandMetadata ownership", () => {
  it("keeps the neutral contract exact and all five consumers independent", () => {
    const metadataSource = readSource("lesson-command-metadata.ts");
    const lessonCommandSource = readSource("lesson-command.service.ts");
    const schedulePlanSource = readSource("schedule-plan.service.ts");
    const fiveConsumers = [
      lessonCommandSource,
      readSource("lesson-series-command.service.ts"),
      readSource("lesson-settlement-correction.service.ts"),
      readSource("lesson-transition.service.ts"),
      schedulePlanSource,
    ];

    expect(metadataSource).toMatch(
      /export interface LessonCommandMetadata\s*{\s*idempotencyKey: string;\s*requestId: string;\s*}/s,
    );
    expect(
      metadataSource.match(/^\s*[A-Za-z_$][\w$]*\??\s*:/gm),
    ).toHaveLength(2);
    for (const source of fiveConsumers) {
      expect(source).toMatch(/from "\.\/lesson-command-metadata"/);
    }
    expect(lessonCommandSource).toMatch(
      /export type { LessonCommandMetadata } from "\.\/lesson-command-metadata"/,
    );
    expect(schedulePlanSource).not.toMatch(
      /LessonCommandMetadata[^;]*lesson-command\.service/,
    );
  });
});
