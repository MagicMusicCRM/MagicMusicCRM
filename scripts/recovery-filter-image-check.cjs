// Contract check against compiled classes in an actual, network-isolated image.
const { execFileSync } = require('node:child_process');
const assert = require('node:assert/strict');
const image = process.argv[2];
assert(/^magicmusiccrm-server:[\w.+-]+$/.test(image));
const code = `
require('reflect-metadata');
const assert = require('node:assert/strict');
const { ValidationPipe } = require('@nestjs/common');
const { TeacherStatsQuery } = require('./dist/crm/dto/teacher-stats.query');
const { TeacherStatsReportService } = require('./dist/crm/payroll/teacher-stats-report.service');
(async () => {
  const query = await new ValidationPipe({transform:true,whitelist:true,forbidNonWhitelisted:true})
    .transform({from:'2026-09-01',to:'2026-10-01',compensationRuleKey:'trial_lesson'},
      {type:'query',metatype:TeacherStatsQuery});
  const service = new TeacherStatsReportService(null,null,null);
  const rows = [{id:'trial',compensation_rule_key:'trial_lesson'},
    {id:'paid',compensation_rule_key:'standard'}];
  assert.deepEqual(service.filterLessons(rows, query).map(x=>x.id), ['trial']);
  assert.deepEqual(service.filterLessons(rows, {}).map(x=>x.id), ['trial','paid']);
  console.log('PASS compiled DTO accepts filter and service excludes other rules');
})().catch(error => {console.error(error.message);process.exitCode=1;});`;
execFileSync('docker', ['run', '--rm', '--network', 'none', '--pull', 'never',
  image, 'node', '-e', code], { stdio: 'inherit', windowsHide: true });
