const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path');
async function runPayrollExportAudit({fixture,baseUrl,output,check}){
 assert.equal(new URL(baseUrl).hostname,'127.0.0.1');const evidence=[];
 for(const role of ['manager','director']){
  const account=fixture.clientAuditAccounts.find(a=>a.role===role),login=await fetch(baseUrl+'/auth/login',{method:'POST',headers:{'content-type':'application/json'},body:JSON.stringify({email:account.email,password:fixture.password})});assert.equal(login.status,200);const session=(await login.json()).session;
  const r=await fetch(baseUrl+'/crm/reports/teacher-stats/export',{headers:{authorization:'Bearer '+session.accessToken}}),bytes=Buffer.from(await r.arrayBuffer());
  const row={role,status:r.status,contentType:r.headers.get('content-type'),bytes:bytes.length,prefix:bytes.subarray(0,32).toString(),zipMagic:bytes.subarray(0,4).equals(Buffer.from([80,75,3,4]))};
  if(!row.zipMagic){try{const json=JSON.parse(bytes.toString());row.jsonType=json.type;row.embeddedBufferLength=json.data?.length;row.embeddedZipMagic=Buffer.from(json.data??[]).subarray(0,4).equals(Buffer.from([80,75,3,4]));if(row.embeddedZipMagic){fs.writeFileSync(path.join(output,role+'-embedded.xlsx'),Buffer.from(json.data));}}catch{}}
  fs.writeFileSync(path.join(output,role+'-export-response.bin'),bytes);evidence.push(row);fs.writeFileSync(path.join(output,'payroll-export-audit.json'),JSON.stringify(evidence,null,2));
  await check(role+' payroll export must send XLSX bytes',async()=>{assert.equal(r.status,200);assert.equal(row.zipMagic,true,'Endpoint must return ZIP/XLSX bytes, not JSON serialization of Buffer');});
 }
}
module.exports={runPayrollExportAudit};
