const assert=require('node:assert/strict'),{randomUUID}=require('node:crypto'),fs=require('node:fs'),path=require('node:path');
async function runDataQualityBoundaryAudit({pool,fixture,baseUrl,output,check}) {
 assert.equal(new URL(baseUrl).hostname,'127.0.0.1');const tokens={},requests=[],steps=[],facts=[];let currentStep='setup';
 const save=()=>fs.writeFileSync(path.join(output,'data-quality-boundaries.json'),JSON.stringify({requests,steps,facts},null,2));
 async function call(role,method,endpoint,body){const response=await fetch(baseUrl+endpoint,{method,headers:{'content-type':'application/json','idempotency-key':randomUUID(),'x-request-id':randomUUID(),...(tokens[role]?{authorization:'Bearer '+tokens[role]}:{})},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(15000)});const data=await response.json();requests.push({step:currentStep,role,method,endpoint,status:response.status,...(endpoint==='/auth/login'?{}:{data})});save();return {status:response.status,data};}
 const ok=r=>{assert([200,201].includes(r.status),'Expected success: '+r.status);return r.data;};const denied=r=>assert([403,404].includes(r.status),'Expected scoped denial, got '+r.status);
 async function verify(id,role,description,work){currentStep=id;await check(id+': '+description,async()=>{try{await work();steps.push({id,role,description,status:'PASS'});}catch(error){steps.push({id,role,description,status:'FAIL',failure:error.message});throw error;}finally{save();}});}
 for(const account of fixture.clientAuditAccounts){tokens[account.role]=ok(await call(account.role,'POST','/auth/login',{email:account.email,password:fixture.password})).session.accessToken;}
 const branch=ok(await call('director','POST','/crm/branches',{name:'DATA-FOREIGN',weeklyHours:[{weekday:1,open:'08:00',close:'22:00'}]}));
 const cases={};for(const [index,role] of ['admin','manager'].entries()) {const winner=randomUUID(),loser=randomUUID(),queue=randomUUID(),phone='+7999444000'+index;
  await pool.query("insert into app.leads(id,first_name,last_name,phone,phone_normalized,branch_id) values($1,$3,'Чужой',$4,$4,$5),($2,$3,'Чужой',$4,$4,$5)",[winner,loser,'BOUNDARY-'+role,phone,branch.id]);
  await pool.query("insert into app.phone_review_queue(id,entity_type,entity_id,raw_phone,reason) values($1,'lead',$2,'123','too_short')",[queue,loser]);cases[role]={winner,loser,queue};
 }
 facts.push({cases,foreignBranch:branch.id});save();
 for(const role of ['admin','manager']) {const c=cases[role];
  await verify(role+'-BASE-CARD',role,'Чужая карточка лида отклоняется обычным API',async()=>denied(await call(role,'GET','/crm/leads/'+c.loser+'/card')));
  await verify(role+'-PHONE-LIST',role,'Очередь телефонов исключает чужую карточку',async()=>{const r=ok(await call(role,'GET','/crm/phone-review-queue?limit=200'));assert(!r.items.some(r=>r.id===c.queue),'Foreign phone queue row disclosed');});
  await verify(role+'-PHONE-WRITE',role,'Исправление телефона чужого лида отклоняется',async()=>denied(await call(role,'PATCH','/crm/phone-review-queue/'+c.queue,{action:'accepted_as_is',resolutionNote:'AUDIT-FOREIGN-PHONE'})));
  await verify(role+'-MERGE-LIST',role,'Список дублей исключает чужие карточки',async()=>{const r=ok(await call(role,'GET','/crm/merge-candidates?limit=200'));assert(!r.items.some(r=>[r.loserId,r.winnerId].includes(c.loser)),'Foreign merge candidate disclosed');});
  let merge;
  await verify(role+'-MERGE-WRITE',role,'Объединение чужих лидов отклоняется',async()=>{const r=await call(role,'POST','/crm/leads/'+c.winner+'/merge/'+c.loser,{});if([200,201].includes(r.status))merge=r.data.mergeLogId;denied(r);});
  if(merge)await verify(role+'-MERGE-UNDO',role,'Отмена чужого объединения также требует scope',async()=>denied(await call(role,'POST','/crm/merges/'+merge+'/undo',{})));
 }
 for(const role of ['client','teacher']){
  await verify(role+'-PHONE-WRITE',role,'Роль без прав изменения не разбирает очередь',async()=>denied(await call(role,'PATCH','/crm/phone-review-queue/'+randomUUID(),{action:'accepted_as_is',resolutionNote:'AUDIT-DENIED'})));
  await verify(role+'-MERGE-WRITE',role,'Роль без прав изменения не объединяет лиды',async()=>denied(await call(role,'POST','/crm/leads/'+cases.admin.winner+'/merge/'+cases.admin.loser,{})));
 }
 const leads=(await pool.query('select id,deleted_at,version from app.leads where id=any($1::uuid[]) order by id',[Object.values(cases).flatMap(c=>[c.winner,c.loser])])).rows;
 const queue=(await pool.query('select id,resolved_at,resolution_note from app.phone_review_queue where id=any($1::uuid[]) order by id',[Object.values(cases).map(c=>c.queue)])).rows;
 const history=(await pool.query('select id,loser_id,winner_id,merged_by,undone_by,undone_at from app.merge_log order by merged_at')).rows;
 facts.push({leads,queue,history});save();
}
module.exports={runDataQualityBoundaryAudit};
