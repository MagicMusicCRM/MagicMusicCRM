// Zero-write preview of what the corrected import would load, computed locally
// from the HolliHop dump (uses the materialized Days occurrences). No DB, no API.
//   node server/scripts/preview-import.mjs
import { readFileSync } from "node:fs";
const load = (n) => JSON.parse(readFileSync(`hollihop-dump/${n}.json`, "utf8"));
const FROM = "2024-01-01", TO = "2028-01-01";

const edunits = load("EdUnits");
const eus = load("EdUnitStudents");
const students = load("Students");
const leads = load("Leads");
const payments = load("Payments");

// members per unit (Individual/Group memberships; Trial units have none)
const members = new Map();
for (const e of eus) {
  const k = String(e.EdUnitId);
  if (!members.has(k)) members.set(k, new Set());
  members.get(k).add(String(e.StudentClientId));
}

const inRange = (d) => d && d >= FROM && d < TO;
let lessonsTotal = 0, lessonsSolo = 0, lessonsGroup = 0, lessonsTrial = 0;
let unitsSolo = 0, unitsGroup = 0, unitsTrial = 0, unitsNoStudent = 0;
const rooms = new Set();
const byType = {};

for (const u of edunits) {
  byType[u.Type] = (byType[u.Type] || 0) + 1;
  const m = members.get(String(u.Id)) || new Set();
  const solo = m.size === 1;
  const isTrial = u.Type === "TrialLesson";
  // count this unit's actual occurrences in range
  const days = (u.Days || []).filter((d) => inRange(String(d.Date).slice(0, 10)));
  lessonsTotal += days.length;
  if (solo) { unitsSolo++; lessonsSolo += days.length; }
  else if (m.size > 1) { unitsGroup++; lessonsGroup += days.length; }
  else if (isTrial) { unitsTrial++; lessonsTrial += days.length; }
  else { unitsNoStudent++; }
  for (const si of u.ScheduleItems || []) if (si.ClassroomName) rooms.add((u.OfficeOrCompanyName || "?") + " | " + si.ClassroomName);
}

console.log("=== PREVIEW: corrected HolliHop import (zero writes) ===");
console.log("EdUnit types:", JSON.stringify(byType));
console.log("");
console.log("LESSONS (from HolliHop Days occurrences, 2024-2028):");
console.log("  total lesson occurrences:        ", lessonsTotal);
console.log("  → with student_id (individual):  ", lessonsSolo, `(from ${unitsSolo} units)`);
console.log("  → group lessons (+participation):", lessonsGroup, `(from ${unitsGroup} units)`);
console.log("  → trial lessons (prospect name): ", lessonsTrial, `(from ${unitsTrial} units)`);
console.log("  units with no resolvable student:", unitsNoStudent);
console.log("");
console.log("ENTITIES that would be upserted (idempotent by deterministic id):");
console.log("  students:", students.length, "| leads:", leads.length, "| payments:", payments.length);
console.log("  distinct rooms (office×classroom):", rooms.size, "—", [...rooms].join("; "));
console.log("");
console.log("vs CURRENT DB: 35149 lessons but only 5 with a student → after import the");
console.log("vast majority of individual lessons become student-attached and visible in");
console.log("the client card. Phone trigger normalizes every imported phone on write.");
