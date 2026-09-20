const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{randomUUID}=require('node:crypto');
async function runCommentRulesAudit({pool,fixture,baseUrl,output,check}){
 assert.equal(new URL(baseUrl).hostname,'127.0.0.1');const steps=[],requests=[],facts=[],users={};let currentStep='setup';
 const save=()=>fs.writeFileSync(path.join(output,'comment-rules.json'),JSON.stringify({steps,requests,facts},null,2));
 async function call(role,method,endpoint,data){const r=await fetch(baseUrl+endpoint,{method,headers:{'content-type':'application/json','idempotency-key':randomUUID(),'x-request-id':randomUUID(),...(users[role]?{authorization:'Bearer '+users[role].token}:{})},body:data===undefined?undefined:JSON.stringify(data),signal:AbortSignal.timeout(15000)});const body=await r.json();requests.push({step:currentStep,role,method,endpoint,status:r.status});save();return{status:r.status,body};}
 const ok=r=>{assert([200,201].includes(r.status),'Unexpected HTTP '+r.status);return r.body;};
 async function verify(id,role,description,work){currentStep=id;await check(id+': '+description,async()=>{try{await work();steps.push({id,role,description,status:'PASS'});}catch(e){steps.push({id,role,description,status:'FAIL',failure:e.message});throw e;}finally{save();}});}
 for(const a of fixture.clientAuditAccounts){const r=ok(await call(a.role,'POST','/auth/login',{email:a.email,password:fixture.password}));users[a.role]={id:r.user.id,token:r.session.accessToken};}
 const student=fixture.students[0],list=async role=>{const r=ok(await call(role,'GET','/crm/comments?entityType=student&entityId='+student));return r.items;};
 const teacherComment=ok(await call('teacher','POST','/crm/comments',{entityType:'student',entityId:student,body:'AUDIT-TEACHER-PERMANENT',kind:'teacher_note'}));
 const original=(await pool.query('select id,author_id,body,kind,created_at,shared_with_teacher,version from app.entity_comments where id=$1',[teacherComment.id])).rows[0];facts.push({step:'created',comment:original});
 for(const role of ['teacher','admin','manager','director'])await verify(role+'-READ',''+role,'Комментарий преподавателя читается в пределах карточки',async()=>{const c=(await list(role)).find(c=>c.id===teacherComment.id);assert(c);assert.equal(c.authorId,users.teacher.id);assert.equal(c.body,'AUDIT-TEACHER-PERMANENT');assert(c.createdAt);assert(c.authorName);});
 for(const role of ['admin','manager','director']){
  await verify(role+'-PERMANENT',role,'Комментарий преподавателя нельзя скрыть от преподавателей',async()=>{
   const row=(await pool.query('select version from app.entity_comments where id=$1',[teacherComment.id])).rows[0];await call(role,'PATCH','/crm/comments/'+teacherComment.id+'/visibility',{expectedVersion:Number(row.version),sharedWithTeacher:false});
   const sql=(await pool.query('select author_id,body,kind,created_at,shared_with_teacher,version from app.entity_comments where id=$1',[teacherComment.id])).rows[0];facts.push({step:currentStep,comment:sql,visibleTeacher:(await list('teacher')).some(c=>c.id===teacherComment.id)});assert.equal(sql.shared_with_teacher,true,'Owner rule: teacher comment must remain teacher-visible');
  });
  await verify(role+'-RESTORE',role,'Возврат видимости сохраняет автора, текст и исходное время',async()=>{
   const row=(await pool.query('select version from app.entity_comments where id=$1',[teacherComment.id])).rows[0];ok(await call(role,'PATCH','/crm/comments/'+teacherComment.id+'/visibility',{expectedVersion:Number(row.version),sharedWithTeacher:true}));
   const sql=(await pool.query('select author_id,body,created_at,shared_with_teacher from app.entity_comments where id=$1',[teacherComment.id])).rows[0];assert.equal(sql.author_id,original.author_id);assert.equal(sql.body,original.body);assert.equal(sql.created_at.toISOString(),original.created_at.toISOString());assert((await list('teacher')).some(c=>c.id===teacherComment.id));facts.push({step:currentStep,comment:sql});
  });
 }
 await verify('CLIENT-HIDDEN','client','Комментарий преподавателя не выдаётся клиенту',async()=>{const r=await call('client','GET','/crm/comments?entityType=student&entityId='+student);assert([200,403].includes(r.status));if(r.status===200)assert(!r.body.items.some(c=>c.id===teacherComment.id));});
 facts.push({step:'SQL',comments:(await pool.query('select c.*,u.role author_role from app.entity_comments c join app.users u on u.id=c.author_id where c.id=$1',[teacherComment.id])).rows});save();
}
module.exports={runCommentRulesAudit};
