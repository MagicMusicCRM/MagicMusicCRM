update app.role_package_capabilities entry
set effect = 'deny'
from app.role_packages package
where entry.package_id = package.id
  and package.active
  and package.role = 'admin'
  and entry.capability_key in ('workflow.task.read', 'workflow.task.write');
