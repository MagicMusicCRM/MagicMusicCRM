const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{randomUUID}=require('node:crypto');
async function runResponsibleAudit({pool,fixture,baseUrl,output,check}){
 assert.equal(new URL(baseUrl).hostname,'127.0.0.1');const steps=[],requests=[],facts=[],users={};let currentStep='setup';
 const save=()=>fs.writeFileSync(path.join(output,'responsible-audit.json'),JSON.stringify({steps,requests,facts},null,2));
 async function call(role,method,endpoint,data){const r=await fetch(baseUrl+endpoint,{method,headers:{'content-type':'application/json',...(users[role]?{authorization:'Bearer '+users[role].token}:{})},body:data===undefined?undefined:JSON.stringify(data),signal:AbortSignal.timeout(15000)});const body=await r.json();requests.push({step:currentStep,role,method,endpoint,status:r.status});save();return{status:r.status,body};}
 const ok=r=>{assert([200,201].includes(r.status),'Unexpected HTTP '+r.status);return r.body;};
 async function verify(id,role,description,work){currentStep=id;await check(id+': '+description,async()=>{try{await work();steps.push({id,role,description,status:'PASS'});}catch(e){steps.push({id,role,description,status:'FAIL',failure:e.message});throw e;}finally{save();}});}
 for(const a of fixture.clientAuditAccounts){const r=ok(await call(a.role,'POST','/auth/login',{email:a.email,password:fixture.password}));users[a.role]={id:r.user.id,token:r.session.accessToken};}
 const ds=(await pool.query("insert into app.staff_members(profile_id,role,status) select id,'director','working' from app.profiles where user_id=$1 returning id",[users.director.id])).rows[0];await pool.query('insert into app.staff_branch_assignments(staff_member_id,branch_id) values($1,$2)',[ds.id,fixture.branch]);
 for(const role of ['admin','manager','director']){
  const id=randomUUID();await pool.query("insert into app.leads(id,first_name,last_name,branch_id) values($1,'До','RESPONSIBLE-AUDIT',$2)",[id,fixture.branch]);
  const read=async()=>{const r=(await pool.query('select id,first_name,assigned_to,custom_data,version from app.leads where id=$1',[id])).rows[0];facts.push({step:currentStep,lead:r,expectedResponsible:users[role].id});save();return r;};
  await verify(role+'-AUTO',role,'Изменение свободного лида назначает редактирующего сотрудника',async()=>{ok(await call(role,'PATCH','/crm/leads/'+id,{firstName:'После',expectedVersion:1}));const r=await read();assert.equal(r.first_name,'После');assert.equal(r.assigned_to,users[role].id,'Successful edit must also claim empty responsible slot');});
  await verify(role+'-EXPLICIT',role,'Явный выбор ответственного сохраняет каноническую связь',async()=>{const r=await read();ok(await call(role,'PATCH','/crm/leads/'+id,{assignedTo:users[role].id,expectedVersion:Number(r.version)}));const s=await read();assert.equal(s.assigned_to,users[role].id);assert.equal(s.custom_data.responsibleUserId,users[role].id);});
  await verify(role+'-CLEAR',role,'Явное снятие ответственного сохраняется без автоназначения',async()=>{const r=await read();ok(await call(role,'PATCH','/crm/leads/'+id,{clearAssignedTo:true,expectedVersion:Number(r.version)}));const s=await read();assert.equal(s.assigned_to,null);assert(!s.custom_data.responsibleUserId);});
  await verify(role+'-INVALID',role,'Нельзя назначить преподавателя ответственным сотрудником',async()=>{const r=await read(),response=await call(role,'PATCH','/crm/leads/'+id,{assignedTo:users.teacher.id,expectedVersion:Number(r.version)});assert.equal(response.status,400);assert.equal((await read()).version,r.version);});
 }
}
module.exports={runResponsibleAudit};
