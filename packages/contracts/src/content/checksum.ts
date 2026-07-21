import { sha256 } from "@noble/hashes/sha2.js";
import { bytesToHex } from "@noble/hashes/utils.js";

import type { Sha256Checksum } from "./types.js";
import { canonicalJson } from "./canonical_json.js";

const UTF8_ENCODER = new TextEncoder();

/** Hashes every canonical package field except a root-level `checksum`. */
export function contentChecksum(value: unknown): Sha256Checksum {
  const canonical = canonicalJson(value, { omitTopLevel: ["checksum"] });
  return `sha256:${bytesToHex(sha256(UTF8_ENCODER.encode(canonical)))}`;
}
