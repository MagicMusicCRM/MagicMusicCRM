import { readFileSync } from "node:fs";

it("keeps versioned contracts inside rollout or migration boundaries", () => {
  const pkg = JSON.parse(readFileSync("package.json", "utf8"));

  expect(pkg.scripts["v7:reconcile"]).toContain(
    "src/migration/commerce/v7/commerce-data.ts",
  );
  expect(pkg.scripts["v4:preflight"]).toContain(
    "src/platform/rollout/v4/preflight.ts",
  );
});
