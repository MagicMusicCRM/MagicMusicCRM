import { buildTextSearch } from "./search-text";

describe("buildTextSearch", () => {
  const makeAdd = (params: unknown[]) => (value: unknown) => {
    params.push(value);
    return `$${params.length}`;
  };

  it("matches a phone typed in any format, not just as stored", () => {
    const params: unknown[] = [];
    const { where } = buildTextSearch({
      q: "89161234567",
      columns: ["p.first_name", "p.phone"],
      phoneColumn: "p.phone",
      add: makeAdd(params),
    });

    // The canonical form is bound, so a number stored as +7916… is reachable
    // by the 8916… people actually type.
    expect(params).toContain("+79161234567");
    expect(where).toContain("regexp_replace");
  });

  it("binds a null phone for a non-phone query, disabling that branch", () => {
    const params: unknown[] = [];
    buildTextSearch({
      q: "Иванов",
      columns: ["p.first_name"],
      phoneColumn: "p.phone",
      add: makeAdd(params),
    });

    expect(params).toContain(null);
    expect(params).not.toContain("+7Иванов");
  });

  it("searches custom_data VALUES, never keys or raw json", () => {
    const params: unknown[] = [];
    const { where } = buildTextSearch({
      q: "гитара",
      columns: ["p.first_name"],
      customDataColumn: "s.custom_data",
      add: makeAdd(params),
    });

    expect(where).toContain("jsonb_each_text(s.custom_data)");
    expect(where).toContain("lower(cd.value) like");
    // Casting the whole document to text is what made a search for "level"
    // match every row that merely has that key.
    expect(where).not.toContain("custom_data::text");
  });

  it("escapes LIKE wildcards so '%' is not a match-everything query", () => {
    const params: unknown[] = [];
    buildTextSearch({
      q: "100%_x",
      columns: ["p.first_name"],
      add: makeAdd(params),
    });

    expect(params[0]).toBe("100\\%\\_x");
  });

  it("ranks exact name, then prefix, then word start, then the rest", () => {
    const params: unknown[] = [];
    const { rank } = buildTextSearch({
      q: "иван",
      columns: ["p.first_name", "p.last_name"],
      exactColumn: "concat_ws(' ', p.first_name, p.last_name)",
      add: makeAdd(params),
    });

    const tiers = rank.match(/then \d/g);
    expect(tiers).toEqual(["then 0", "then 1", "then 2"]);
    expect(rank).toContain("lower(concat_ws(' ', p.first_name, p.last_name)) = $1");
    expect(rank).toContain("else 3");
  });

  it("keeps every clause optional-safe: no phone/custom columns, no branches", () => {
    const params: unknown[] = [];
    const { where } = buildTextSearch({
      q: "иван",
      columns: ["l.first_name"],
      add: makeAdd(params),
    });

    expect(where).not.toContain("jsonb_each_text");
    expect(where).not.toContain("regexp_replace");
    expect(params).toEqual(["иван"]);
  });
});
