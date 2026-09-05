import Ajv from 'ajv';
import addFormats from 'ajv-formats';
import type { OpenAPIObject, OperationObject, ParameterObject, ResponseObject, SchemaObject } from '@nestjs/swagger';

/** Validate the OpenAPI schema with no payload coercion or field stripping. */
export function wireContractValidator(document: OpenAPIObject) {
  const ajv = new Ajv({ strict: false, allErrors: true });
  addFormats(ajv);
  function schemaCheck(schema: unknown, value: unknown): void {
    // Local references must resolve against the complete component tree.
    const validate = ajv.compile({ ...(schema as object), components: document.components });
    if (!validate(value)) throw new Error(ajv.errorsText(validate.errors));
  }
  function operation(path: string, method: string): OperationObject {
    const match = Object.entries(document.paths).find(([template]) =>
      new RegExp('^' + template.replace(/\{[^}]+\}/g, '[^/]+') + '$').test(path));
    const result = match?.[1][method.toLowerCase() as 'get'];
    if (!result) throw new Error(`Undocumented operation: ${method} ${path}`);
    return result;
  }
  return {
    schemaCheck,
    request(path: string, method: string, body?: unknown, query: Record<string, unknown> = {}) {
      const op = operation(path, method);
      if (op.requestBody && 'content' in op.requestBody) {
        schemaCheck(op.requestBody.content['application/json'].schema, body);
      }
      const params = (op.parameters ?? []).filter((p): p is ParameterObject => 'in' in p && p.in === 'query');
      schemaCheck({ type: 'object', additionalProperties: false,
        properties: Object.fromEntries(params.map(p => [p.name, p.schema])),
        required: params.filter(p => p.required).map(p => p.name),
      }, query);
    },
    response(path: string, method: string, status: number, body: unknown) {
      const response = operation(path, method).responses[String(status)] as ResponseObject | undefined;
      const schema = response?.content?.['application/json']?.schema as SchemaObject | undefined;
      if (!schema) throw new Error(`Undocumented response: ${method} ${path} ${status}`);
      schemaCheck(schema, body);
    },
  };
}
