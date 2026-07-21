import { z } from "zod";

export const ActivationWorkerRequestSchema = z.object({
  batchLimit: z.number().int().min(1).max(100).optional(),
}).strict();

export type ActivationWorkerRequest = z.infer<typeof ActivationWorkerRequestSchema>;

export interface PublicationActivationRepository {
  listDuePublicationIds(batchLimit: number): Promise<string[]>;
  activatePublication(publicationId: string, requestId: string): Promise<string>;
}

const textEncoder = new TextEncoder();

async function sha256(value: string): Promise<Uint8Array> {
  return new Uint8Array(
    await crypto.subtle.digest("SHA-256", textEncoder.encode(value)),
  );
}

export async function hasValidSchedulerBearer(
  request: Request,
  expectedSecret: string,
): Promise<boolean> {
  const authorization = request.headers.get("authorization") ?? "";
  const match = /^Bearer ([^\s]+)$/i.exec(authorization);
  const suppliedSecret = match?.[1] ?? "";
  const [suppliedDigest, expectedDigest] = await Promise.all([
    sha256(suppliedSecret),
    sha256(expectedSecret),
  ]);

  let difference = 0;
  for (let index = 0; index < expectedDigest.length; index += 1) {
    difference |= suppliedDigest[index] ^ expectedDigest[index];
  }
  return match !== null && difference === 0;
}
