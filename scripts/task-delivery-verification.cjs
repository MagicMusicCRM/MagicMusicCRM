const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{randomUUID}=require('node:crypto');
async function runTaskDeliveryAudit({pool,fixture,baseUrl,output,check}){
 assert.equal(new URL(baseUrl).hostname,'127.0.0.1');const steps=[],requests=[],facts=[],users={};let currentStep='setup';
 const save=()=>fs.writeFileSync(path.join(output,'task-delivery.json'),JSON.stringify({steps,requests,facts},null,2));
 async function call(role,method,endpoint,data,key=randomUUID()){const r=await fetch(baseUrl+endpoint,{method,headers:{'content-type':'application/json','idempotency-key':key,'x-request-id':randomUUID(),...(users[role]?{authorization:'Bearer '+users[role].token}:{})},body:data===undefined?undefined:JSON.stringify(data),signal:AbortSignal.timeout(15000)});const body=await r.json();requests.push({step:currentStep,role,method,endpoint,status:r.status});save();return{status:r.status,body};}
 const ok=r=>{assert([200,201].includes(r.status),'Unexpected HTTP '+r.status);return r.body;};
 async function verify(id,role,description,work){currentStep=id;await check(id+': '+description,async()=>{try{await work();steps.push({id,role,description,status:'PASS'});}catch(e){steps.push({id,role,description,status:'FAIL',failure:e.message});throw e;}finally{save();}});}
 for(const a of fixture.clientAuditAccounts){const r=ok(await call(a.role,'POST','/auth/login',{email:a.email,password:fixture.password}));users[a.role]={id:r.user.id,token:r.session.accessToken};}
 const tasks={},inputs={};
 for(const variant of ['open','closed','disabled']){
  inputs[variant]={title:'AUDIT-REMINDER-'+variant,allDay:true,startAt:new Date(Date.now()+3600000).toISOString(),audiences:[{type:'user',targetId:users.admin.id}],reminders:[{dueAt:new Date(Date.now()+6000).toISOString(),channel:'in_app'}]};
  await verify('CREATE-'+variant,'director','Создать задачу и напоминание '+variant,async()=>{const key=randomUUID();tasks[variant]=ok(await call('director','POST','/crm/shared-tasks',inputs[variant],key));const replay=ok(await call('director','POST','/crm/shared-tasks',inputs[variant],key));assert.equal(replay.id,tasks[variant].id);});
 }
 assert(Object.values(tasks).every(t=>t.id));
 await verify('CLOSE','admin','Закрыть задачу до срока напоминания',async()=>{ok(await call('admin','POST','/crm/shared-tasks/'+tasks.closed.id+'/close',{expectedVersion:tasks.closed.version}));});
 await verify('DISABLE','director','Убрать напоминание до срока',async()=>{ok(await call('director','PATCH','/crm/shared-tasks/'+tasks.disabled.id,{...inputs.disabled,expectedVersion:tasks.disabled.version,reminders:[]}));});
 const ids=Object.values(tasks).map(t=>t.id);
 async function snapshot(){return{reminders:(await pool.query('select * from app.shared_task_reminders where task_id=any($1::uuid[]) order by task_id',[ids])).rows,notifications:(await pool.query("select id,title,data from app.notifications where data->>'entityId'=any($1::text[]) order by id",[ids])).rows};}
 await verify('DELIVERY','admin','Реальный worker доставляет одно напоминание открытой задачи',async()=>{
  let state;for(let i=0;i<80;i++){state=await snapshot();if(state.notifications.some(n=>n.data.entityId===tasks.open.id))break;await new Promise(r=>setTimeout(r,500));}
  facts.push({step:currentStep,...state});assert.equal(state.notifications.filter(n=>n.data.entityId===tasks.open.id).length,1);
  const list=ok(await call('admin','GET','/notifications?limit=100'));facts.push({step:currentStep,list});assert(JSON.stringify(list).includes(tasks.open.id));
 });
 await verify('CLOSED-NO-DELIVERY','admin','Закрытая задача не доставляет напоминание',async()=>{assert.equal((await snapshot()).notifications.filter(n=>n.data.entityId===tasks.closed.id).length,0);});
 await verify('DISABLED-NO-DELIVERY','admin','Отключённое напоминание не доставляется',async()=>{assert.equal((await snapshot()).notifications.filter(n=>n.data.entityId===tasks.disabled.id).length,0);});
 await verify('SCOPE','teacher','Уведомление конкретного сотрудника не видно преподавателю',async()=>{const list=ok(await call('teacher','GET','/notifications?limit=100'));assert(!JSON.stringify(list).includes(tasks.open.id));});
 await verify('NEXT-TICK','admin','Следующий настоящий tick не дублирует доставку',async()=>{await new Promise(r=>setTimeout(r,31000));const state=await snapshot();facts.push({step:currentStep,...state});assert.equal(state.notifications.length,1);assert.equal(state.reminders.find(r=>r.task_id===tasks.open.id).status,'delivered');});
 save();
}
module.exports={runTaskDeliveryAudit};
