import { spawnSync } from "node:child_process";
import { fileURLToPath, pathToFileURL } from "node:url";

import { describe, expect, it } from "vitest";

import { verifyGeneratedAnswer } from "../../src/content/generation/independent_verify.js";

const LARGE_SAFE_PRIME = 9_007_199_254_740_881;

describe("independent generated-answer verification", () => {
  it("keeps valid maximum-domain number-theory checks within a bounded runtime", () => {
    const moduleUrl = pathToFileURL(
      fileURLToPath(new URL("../../src/content/generation/independent_verify.ts", import.meta.url)),
    ).href;
    const script = `
      import { verifyGeneratedAnswer } from ${JSON.stringify(moduleUrl)};

      const prime = ${LARGE_SAFE_PRIME};
      const lcmIssues = verifyGeneratedAnswer(
        "common_multiple_v1",
        { operands: [prime, 1], operator: "lcm", answer: prime },
        { kind: "integer", value: prime },
      );
      const factorIssues = verifyGeneratedAnswer(
        "prime_factorization_v1",
        { value: prime, factors: [prime], factor_count: 1, allowed_primes: [prime] },
        { kind: "integer_list", values: [prime], order_matters: false },
      );
      if (lcmIssues.length !== 0 || factorIssues.length !== 0) {
        throw new Error(JSON.stringify({ lcmIssues, factorIssues }));
      }
    `;

    const result = spawnSync(
      process.execPath,
      ["--import", "tsx", "--input-type=module", "--eval", script],
      { encoding: "utf8", timeout: 2_000 },
    );

    expect(result.error).toBeUndefined();
    expect(result.status, `${result.stderr}\n${result.stdout}`).toBe(0);
  });

  it("rejects a large strong pseudoprime as a factor", () => {
    const strongPseudoprime = 341_550_071_728_321;

    expect(
      verifyGeneratedAnswer(
        "prime_factorization_v1",
        { value: strongPseudoprime, factor_count: 1 },
        { kind: "integer_list", values: [strongPseudoprime], order_matters: false },
      ),
    ).toEqual(["NON_PRIME_FACTOR"]);
  });
});
