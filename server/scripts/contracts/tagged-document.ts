import { INestApplication } from '@nestjs/common';
import { DocumentBuilder, OpenAPIObject, SwaggerModule } from '@nestjs/swagger';

export function taggedDocument(app: INestApplication, options: { title: string; description: string; tag: string; closedSchemas: string[] }): OpenAPIObject {
  const document = SwaggerModule.createDocument(app, new DocumentBuilder()
    .setTitle(options.title)
    .setDescription(options.description)
    .setVersion('1.0.0')
    .addBearerAuth()
    .build());
  document.paths = Object.fromEntries(Object.entries(document.paths)
    .map(([path, item]) => [path, Object.fromEntries(Object.entries(item)
      .filter(([, operation]) => operation?.tags?.includes(options.tag)))])
    .filter(([, item]) => Object.keys(item as object).length > 0));
  // Export only reachable schemas; do not imply coverage of unannotated routes.
  const all = document.components?.schemas ?? {};
  const used = new Set<string>();
  function visit(value: unknown): void {
    if (!value || typeof value !== 'object') return;
    for (const [key, child] of Object.entries(value)) {
      if (key === '$ref' && typeof child === 'string' && child.startsWith('#/components/schemas/')) {
        const name = child.slice('#/components/schemas/'.length);
        if (!used.has(name)) { used.add(name); visit(all[name]); }
      } else visit(child);
    }
  }
  visit(document.paths);
  document.components!.schemas = Object.fromEntries([...used].sort().map(name => [name, all[name]]));
  for (const name of options.closedSchemas) {
    Object.assign(document.components!.schemas![name], { additionalProperties: false });
  }
  return document;
}
