import { readFileSync, readdirSync } from "node:fs";
import { basename, resolve } from "node:path";

const studentsDirectory = __dirname;
const crmDirectory = resolve(studentsDirectory, "..");

const readSource = (path: string) => readFileSync(path, "utf8");

const facade = readSource(resolve(crmDirectory, "crm.service.ts"));
const crmModule = readSource(resolve(crmDirectory, "crm.module.ts"));
const executor = readSource(
  resolve(studentsDirectory, "student-mutation.executor.ts"),
);
const command = readSource(
  resolve(studentsDirectory, "student-command.service.ts"),
);

const productionBoundaryFiles = [
  resolve(crmDirectory, "crm.service.ts"),
  ...readdirSync(studentsDirectory)
    .filter((name) => name.endsWith(".ts") && !name.endsWith(".spec.ts"))
    .map((name) => resolve(studentsDirectory, name)),
];

const facadeMethodNames = [
  "getMySummary",
  "listStudents",
  "searchStudents",
  "createStudent",
  "getStudent",
  "getStudentCard",
  "listStudentGroups",
  "updateStudent",
  "inviteStudent",
  "listGroupStudents",
  "deleteStudent",
  "returnStudentToLead",
] as const;

const injectableOwners = [
  "StudentDirectoryService",
  "StudentSelfSummaryService",
  "StudentCardTimelineService",
  "StudentMutationExecutor",
  "StudentCommandService",
] as const;

const transactionBoundaryCount = (source: string) =>
  source.match(/\.transaction\s*\(/g)?.length ?? 0;

const sourceNloc = (source: string) => {
  const withoutBlockComments = source.replace(/\/\*[\s\S]*?\*\//g, "");
  return withoutBlockComments
    .split(/\r?\n/)
    .filter((line) => {
      const trimmed = line.trim();
      return trimmed.length > 0 && !trimmed.startsWith("//");
    }).length;
};

const arraySection = (source: string, property: string) => {
  const propertyStart = source.indexOf(`${property}:`);
  if (propertyStart < 0) {
    throw new Error(`Missing ${property} section`);
  }

  const arrayStart = source.indexOf("[", propertyStart);
  let depth = 0;
  for (let index = arrayStart; index < source.length; index += 1) {
    if (source[index] === "[") {
      depth += 1;
    } else if (source[index] === "]") {
      depth -= 1;
      if (depth === 0) {
        return source.slice(arrayStart + 1, index);
      }
    }
  }

  throw new Error(`Unclosed ${property} section`);
};

describe("CRM student service boundaries", () => {
  it("keeps the compatibility facade small and free of persistence", () => {
    const facadeNloc = sourceNloc(facade);

    expect(facadeNloc).toBeLessThanOrEqual(120);
    expect(facade).not.toMatch(
      /database\.|\.transaction\(|select\s|insert\s|update\s|delete\s/i,
    );
  });

  it("keeps exactly the twelve controller-facing facade methods", () => {
    const declaredMethods = facadeMethodNames.filter((name) =>
      new RegExp(`^\\s*${name}\\s*\\(`, "m").test(facade),
    );

    expect(declaredMethods).toEqual(facadeMethodNames);
  });

  it("keeps both transaction callbacks in the mutation executor only", () => {
    expect(transactionBoundaryCount(executor)).toBe(2);
    expect(command).not.toMatch(/\.transaction\(/);

    const transactionOwners = productionBoundaryFiles
      .filter((path) => transactionBoundaryCount(readSource(path)) > 0)
      .map((path) => basename(path));

    expect(transactionOwners).toEqual(["student-mutation.executor.ts"]);
  });

  it("registers every extracted owner privately in CrmModule", () => {
    const providers = arraySection(crmModule, "providers");
    const exports = arraySection(crmModule, "exports");

    for (const owner of injectableOwners) {
      expect(providers).toMatch(new RegExp(`\\b${owner}\\b`));
      expect(exports).not.toMatch(new RegExp(`\\b${owner}\\b`));
    }
  });
});
