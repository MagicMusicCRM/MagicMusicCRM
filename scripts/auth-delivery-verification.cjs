const assert=require('node:assert/strict'),fs=require('node:fs'),path=require('node:path'),{randomUUID}=require('node:crypto');
async function runAuthDeliveryAudit({pool,fixture,baseUrl,output,check,smtp}){
 assert.equal(new URL(baseUrl).hostname,'127.0.0.1');const steps=[],requests=[],facts=[];let currentStep='setup';
 const save=()=>fs.writeFileSync(path.join(output,'auth-delivery.json'),JSON.stringify({steps,requests,facts},null,2));
 async function call(endpoint,body,bearer){const r=await fetch(baseUrl+'/auth'+endpoint,{method:'POST',headers:{'content-type':'application/json',...(bearer?{authorization:'Bearer '+bearer}:{})},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});const data=await r.json();requests.push({step:currentStep,endpoint,status:r.status,code:data.code});save();return{status:r.status,data};}
 const expect=(r,status)=>{assert.equal(r.status,status,'HTTP status at '+currentStep);return r.data;};
 async function verify(id,role,description,work){currentStep=id;await check(id+': '+description,async()=>{try{await work();steps.push({id,role,description,status:'PASS'});}catch(e){steps.push({id,role,description,status:'FAIL',failure:e.message});throw e;}finally{save();}});}
 async function codeFor(email,after){const m=await smtp.waitFor(email,after),code=m.body.match(/\b[1-9][0-9]{5}\b/)?.[0];assert(code,'SMTP body includes six-digit code');facts.push({step:currentStep,smtpDelivered:true,recipientSynthetic:email.endsWith('@example.test')});return code;}
 for(const account of fixture.clientAuditAccounts.filter(a=>['admin','manager','director'].includes(a.role))){
  const role=account.role,email='otp-'+account.email;await pool.query('update app.users set email=$1 where lower(email)=lower($2)',[email,account.email]);let code,session;
  await verify(role+'-CHALLENGE',role,'Пароль требует OTP и письмо доставлено локальным SMTP',async()=>{const n=smtp.messages.length,r=expect(await call('/login',{email,password:fixture.password}),200);assert.equal(r.emailOtpRequired,true);assert(!r.session);code=await codeFor(email,n);});
  await verify(role+'-WRONG',role,'Неверный код не выдаёт сессию',async()=>expect(await call('/otp/verify',{email,code:'000000'}),400));
  await verify(role+'-VERIFY',role,'Код из доставленного письма выдаёт правильную роль',async()=>{const r=expect(await call('/otp/verify',{email,code}),200);assert.equal(r.user.role,role);assert(r.session.accessToken);session=r.session;});
  await verify(role+'-REUSE',role,'Использованный код нельзя применить повторно',async()=>expect(await call('/otp/verify',{email,code}),400));
 }
 const email='signup-'+randomUUID()+'@example.test',password='Audit-Password-73!',newPassword='Audit-Replaced-84!';let code,user,session,reset;
 await verify('client-SIGNUP','client','Самостоятельная регистрация создаёт только клиента и письмо',async()=>{const n=smtp.messages.length,r=expect(await call('/signup',{email,password,fullName:'Аудит Регистрации'}),201);user=r.user;assert.equal(user.role,'client');assert.equal(r.emailVerificationRequired,true);assert(!r.session);code=await codeFor(email,n);});
 await verify('client-UNVERIFIED','client','Вход до подтверждения почты запрещён',async()=>expect(await call('/login',{email,password}),401));
 await verify('client-VERIFY','client','Подтверждение почты сохраняется, пароль открывает кабинет',async()=>{expect(await call('/otp/verify',{email,code}),200);session=expect(await call('/login',{email,password}),200).session;assert(session.accessToken);});
 await verify('client-DUPLICATE','client','Повторная регистрация не создаёт дубль',async()=>expect(await call('/signup',{email,password,fullName:'Повтор'}),409));
 await verify('client-ROLE-INJECTION','client','Регистрация не принимает назначение роли директора',async()=>expect(await call('/signup',{email:'role-'+email,password,fullName:'Аудит Роли',role:'director'}),400));
 await verify('client-RESET-REQUEST','client','Сброс пароля доставляет отдельный код через SMTP',async()=>{const n=smtp.messages.length;expect(await call('/password-reset/request',{email}),200);reset=await codeFor(email,n);});
 await verify('client-RESET','client','Код меняет пароль, старый пароль больше не принимается',async()=>{expect(await call('/password-reset/confirm',{token:reset,password:newPassword}),200);expect(await call('/login',{email,password}),401);assert(expect(await call('/login',{email,password:newPassword}),200).session.accessToken);});
 await verify('client-RESET-REUSE','client','Повторный сброс с использованным кодом запрещён',async()=>expect(await call('/password-reset/confirm',{token:reset,password}),400));
 await verify('client-RESET-REVOKES','client','Сброс отзывает refresh прежней сессии',async()=>expect(await call('/refresh',{refreshToken:session.refreshToken}),401));
 let rotated;
 await verify('client-REFRESH','client','Refresh меняется и выдаёт новую сессию',async()=>{session=expect(await call('/login',{email,password:newPassword}),200).session;rotated=expect(await call('/refresh',{refreshToken:session.refreshToken}),200).session;assert(rotated.refreshToken&&rotated.refreshToken!==session.refreshToken);});
 await verify('client-REFRESH-REUSE','client','Повтор старого refresh отзывает всё семейство',async()=>{expect(await call('/refresh',{refreshToken:session.refreshToken}),401);expect(await call('/refresh',{refreshToken:rotated.refreshToken}),401);});
 await verify('client-LOGOUT-ALL','client','Выход со всех устройств отзывает две независимые сессии',async()=>{const a=expect(await call('/login',{email,password:newPassword}),200).session,b=expect(await call('/login',{email,password:newPassword}),200).session;expect(await call('/logout-all',{},a.accessToken),200);expect(await call('/refresh',{refreshToken:a.refreshToken}),401);expect(await call('/refresh',{refreshToken:b.refreshToken}),401);});
 if(user){const r=await pool.query('select role,email_verified_at is not null verified,(select count(*)::int from app.refresh_sessions s where s.user_id=u.id and s.revoked_at is null) live_sessions from app.users u where id=$1',[user.id]);facts.push({step:'SQL',users:r.rows});save();}
}
module.exports={runAuthDeliveryAudit};
