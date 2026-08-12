import { BadRequestException } from "@nestjs/common";

export interface VersionedMutationMetadata {
  idempotencyKey: string;
  requestId: string;
}

export function assertVersionedMutationMetadata(
  metadata: VersionedMutationMetadata,
): void {
  if (!/^[A-Za-z0-9._:-]{8,160}$/.test(metadata.idempotencyKey)) {
    throw new BadRequestException({
      code: "IDEMPOTENCY_KEY_REQUIRED",
      message: "Передайте корректный Idempotency-Key.",
    });
  }
  if (
    !metadata.requestId.trim() ||
    metadata.requestId.length > 160 ||
    /[\r\n\0]/.test(metadata.requestId)
  ) {
    throw new BadRequestException({
      code: "REQUEST_ID_REQUIRED",
      message: "Передайте корректный X-Request-Id.",
    });
  }
}
