// Analyze the HolliHop dump to plan the filter + load. Read-only.
//   node server/scripts/analyze-hollihop-dump.mjs
import { readFileSync } from "node:fs";
const DIR = "hollihop-dump";
const load = (n) => JSON.parse(readFileSync(`${DIR}/${n}.json`, "utf8"));
const keys = (arr) => (arr[0] ? Object.keys(arr[0]).join(", ") : "(empty)");

const norm = (raw) => {
  const d = String(raw ?? "").replace(/\D/g, "");
  if (d.length === 11 && (d[0] === "7" || d[0] === "8")) return "+7" + d.slice(1);
  if (d.length === 10 && d[0] === "9") return "+7" + d;
  return null;
};
// HolliHop phone fields vary; gather from common keys.
const phoneOf = (r) => norm(r.Mobile ?? r.Phone ?? r.AgentMobile ?? r.AgentPhone ?? r.Mobile2 ?? "");

const students = load("Students");
const leads = load("Leads");
const edunits = load("EdUnits");
const eus = load("EdUnitStudents");
const payments = load("Payments");

console.log("== STUDENTS (" + students.length + ") ==");
console.log("keys:", keys(students));
{
  const withPhone = students.filter((s) => phoneOf(s)).length;
  const phones = students.map(phoneOf).filter(Boolean);
  const dup = new Map();
  for (const p of phones) dup.set(p, (dup.get(p) || 0) + 1);
  const dupGroups = [...dup.values()].filter((c) => c > 1).length;
  console.log(`  with RU phone: ${withPhone} | distinct phones: ${dup.size} | dup-phone groups: ${dupGroups}`);
  const commentKeys = Object.keys(students[0] || {}).filter((k) => /comment|note|agent|status/i.test(k));
  console.log("  comment/note-ish keys:", commentKeys.join(", ") || "(none)");
}

console.log("== LEADS (" + leads.length + ") ==");
console.log("keys:", keys(leads));
{
  const withPhone = leads.filter((l) => phoneOf(l)).length;
  const phones = leads.map(phoneOf).filter(Boolean);
  const dup = new Map();
  for (const p of phones) dup.set(p, (dup.get(p) || 0) + 1);
  console.log(`  with RU phone: ${withPhone} | distinct phones: ${dup.size} | dup-phone groups: ${[...dup.values()].filter((c) => c > 1).length}`);
  const commentKeys = Object.keys(leads[0] || {}).filter((k) => /comment|note|agent/i.test(k));
  console.log("  comment/note-ish keys:", commentKeys.join(", ") || "(none)");
}

console.log("== CROSS: phone shared between student and lead ==");
{
  const sp = new Set(students.map(phoneOf).filter(Boolean));
  const shared = new Set(leads.map(phoneOf).filter((p) => p && sp.has(p)));
  console.log(`  phones present as BOTH student and lead: ${shared.size}`);
}

console.log("== EDUNITS (" + edunits.length + ") ==");
console.log("keys:", keys(edunits));
{
  const byType = {};
  let siTotal = 0, withDays = 0, frag = 0;
  for (const u of edunits) {
    byType[u.Type] = (byType[u.Type] || 0) + 1;
    const si = (u.ScheduleItems || []).slice().sort((a, b) => String(a.BeginDate + a.BeginTime).localeCompare(String(b.BeginDate + b.BeginTime)));
    siTotal += si.length;
    if ((u.Days || []).length) withDays++;
    // contiguous fragmentation within a unit: same room, A.EndTime == B.BeginTime
    for (let i = 0; i < si.length; i++)
      for (let j = 0; j < si.length; j++)
        if (i !== j && si[i].ClassroomId === si[j].ClassroomId && si[i].EndTime && si[i].EndTime === si[j].BeginTime) frag++;
  }
  console.log("  Type distribution:", JSON.stringify(byType));
  console.log(`  total ScheduleItems: ${siTotal} | units with Days: ${withDays} | contiguous-fragment pairs (same unit/room): ${frag}`);
}

console.log("== EDUNITSTUDENTS (" + eus.length + ") ==");
console.log("keys:", keys(eus));
{
  const studentsPerUnit = new Map();
  for (const e of eus) {
    const uid = e.EdUnitId;
    if (!studentsPerUnit.has(uid)) studentsPerUnit.set(uid, new Set());
    studentsPerUnit.get(uid).add(e.StudentClientId ?? e.StudentId ?? e.ClientId);
  }
  const sizes = [...studentsPerUnit.values()].map((s) => s.size);
  const solo = sizes.filter((n) => n === 1).length;
  console.log(`  units with members: ${studentsPerUnit.size} | single-student (individual) units: ${solo} | multi-student: ${sizes.filter((n) => n > 1).length}`);
}

console.log("== PAYMENTS (" + payments.length + ") ==");
console.log("keys:", keys(payments));
{
  const withClient = payments.filter((p) => p.ClientId != null).length;
  const sum = payments.reduce((a, p) => a + (Number(p.Value) || 0), 0);
  console.log(`  with ClientId: ${withClient} | total Value: ${sum}`);
}
