// server/src/migration/hollihop-mappers.ts
// Pure HolliHop → normalized-row mappers. No DB / IO. Unit-tested.

function asArray(value: unknown): unknown[] {
  return Array.isArray(value) ? value : [];
}
function str(value: unknown): string | null {
  if (typeof value === "string") {
    const t = value.trim();
    return t.length ? t : null;
  }
  return null;
}

// Distinct discipline names (dedup by lower/trim), order preserved, first = primary.
export function disciplineEntries(raw: unknown): { name: string; isPrimary: boolean }[] {
  const seen = new Set<string>();
  const out: { name: string; isPrimary: boolean }[] = [];
  for (const item of asArray(raw)) {
    const name =
      typeof item === "string"
        ? str(item)
        : str((item as Record<string, unknown>)?.["Discipline"]) ??
          str((item as Record<string, unknown>)?.["Name"]);
    if (!name) continue;
    const key = name.toLowerCase();
    if (seen.has(key)) continue;
    seen.add(key);
    out.push({ name, isPrimary: out.length === 0 });
  }
  return out;
}

// Contact persons from HolliHop Agents[]: keep any with a normalizable phone OR a name.
export function contactEntries(
  rawAgents: unknown,
  normalize: (p: string | null | undefined) => string | null,
): { phoneNormalized: string | null; name: string | null; role: string | null }[] {
  const out: { phoneNormalized: string | null; name: string | null; role: string | null }[] = [];
  for (const agent of asArray(rawAgents)) {
    const a = (agent ?? {}) as Record<string, unknown>;
    const phone = normalize(str(a["Mobile"]) ?? str(a["Phone"]));
    const name =
      [str(a["FirstName"]), str(a["LastName"])].filter(Boolean).join(" ").trim() ||
      str(a["Name"]) ||
      null;
    if (!phone && !name) continue;
    out.push({ phoneNormalized: phone, name: name || null, role: str(a["Type"]) ?? str(a["Role"]) });
  }
  return out;
}

export function primaryBranchId(branchIds: string[] | null | undefined): string | null {
  return Array.isArray(branchIds) && branchIds.length ? branchIds[0] : null;
}
