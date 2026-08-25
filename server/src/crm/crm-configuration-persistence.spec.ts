import type { QueryResult, QueryResultRow } from "pg";
import { buildCrmConfigurationBaseline } from "./crm-configuration-baseline";
import {
  CrmConfigurationQueryable,
  resolveEffectiveCrmConfiguration,
} from "./crm-configuration-persistence";

function queryResult<T extends QueryResultRow>(rows: T[]): QueryResult<T> {
  return {
    command: "SELECT",
    rowCount: rows.length,
    oid: 0,
    fields: [],
    rows,
  };
}

describe("CRM configuration persistence", () => {
  it("resolves the school revision through the caller-supplied executor", async () => {
    const snapshot = buildCrmConfigurationBaseline([]);
    const queryable = {
      query: async () =>
        queryResult([
          {
            version: 7,
            effective_snapshot: snapshot,
          },
        ]),
    } as unknown as CrmConfigurationQueryable;

    await expect(resolveEffectiveCrmConfiguration(queryable)).resolves.toEqual({
      schoolVersion: 7,
      branchVersion: 0,
      schoolSnapshot: snapshot,
      snapshot,
    });
  });
});
