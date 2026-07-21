import { z } from "zod";

const MAX_SAFE_INTEGER = Number.MAX_SAFE_INTEGER;
const UUID_V4_PATTERN = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/;
const CANONICAL_UTC_PATTERN = /^(\d{4})-(\d{2})-(\d{2})T(\d{2}):(\d{2}):(\d{2})Z$/;

const safeInteger = z
  .number()
  .int()
  .min(-MAX_SAFE_INTEGER)
  .max(MAX_SAFE_INTEGER);
const nonnegativeSafeInteger = safeInteger.min(0);
const positiveSafeInteger = safeInteger.min(1);
const nonemptyString = z.string().min(1);
const finiteSafeNumber = z.number().min(-MAX_SAFE_INTEGER).max(MAX_SAFE_INTEGER);

const isLeapYear = (year: number): boolean =>
  year % 400 === 0 || (year % 4 === 0 && year % 100 !== 0);

const isCanonicalUtcTimestamp = (value: string): boolean => {
  const match = CANONICAL_UTC_PATTERN.exec(value);
  if (match === null) {
    return false;
  }

  const year = Number(match[1]);
  const month = Number(match[2]);
  const day = Number(match[3]);
  const hour = Number(match[4]);
  const minute = Number(match[5]);
  const second = Number(match[6]);
  if (
    year < 1 ||
    month < 1 ||
    month > 12 ||
    hour > 23 ||
    minute > 59 ||
    second > 59
  ) {
    return false;
  }

  const daysPerMonth = [31, isLeapYear(year) ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  return day >= 1 && day <= (daysPerMonth[month - 1] ?? 0);
};

const canonicalUtcTimestamp = z.string().refine(isCanonicalUtcTimestamp, {
  message: "Expected a calendar-valid canonical UTC timestamp",
});

export const AnswerValueV1Schema = z.discriminatedUnion("kind", [
  z.strictObject({ kind: z.literal("integer"), value: safeInteger }),
  z.strictObject({
    kind: z.literal("integer_list"),
    values: z.array(safeInteger),
    order_matters: z.boolean(),
  }),
]);

const legacyCompatibleAnswerValue = z.union([safeInteger, AnswerValueV1Schema]);
const resolvedParameterValue = z.union([
  z.boolean(),
  z.string(),
  finiteSafeNumber,
  z.array(finiteSafeNumber),
]);
const resolvedParameters = z.record(nonemptyString, resolvedParameterValue);
const rewardMap = z.record(nonemptyString, nonnegativeSafeInteger);

const commonShape = {
  contract_version: z.literal(1),
  event_id: z.string().regex(UUID_V4_PATTERN),
  profile_id: nonemptyString,
  device_id: nonemptyString,
  sequence: positiveSafeInteger,
  client_timestamp: canonicalUtcTimestamp,
} as const;

const requiredSessionShape = { ...commonShape, session_id: nonemptyString } as const;
const optionalSessionShape = { ...commonShape, session_id: nonemptyString.optional() } as const;

const RunStartedEventV1Schema = z.strictObject({
  ...requiredSessionShape,
  event_type: z.literal("run_started"),
  activity_id: nonemptyString,
  content_version: nonemptyString,
});

const AnswerSubmittedEventV1Schema = z.strictObject({
  ...requiredSessionShape,
  event_type: z.literal("answer_submitted"),
  activity_id: nonemptyString,
  content_version: nonemptyString,
  question_seed: nonnegativeSafeInteger,
  generator_id: nonemptyString,
  band_id: nonemptyString,
  resolved_parameters: resolvedParameters,
  submitted_answer: legacyCompatibleAnswerValue,
  correct_answer: legacyCompatibleAnswerValue,
  correctness: z.boolean(),
  response_duration_ms: nonnegativeSafeInteger,
  hints: nonnegativeSafeInteger,
  health_delta: safeInteger,
  combo: nonnegativeSafeInteger,
  reward_delta: rewardMap,
});

const RunCompletedEventV1Schema = z.strictObject({
  ...requiredSessionShape,
  event_type: z.literal("run_completed"),
  completion_reason: nonemptyString,
  final_score: nonnegativeSafeInteger,
  final_health: nonnegativeSafeInteger,
  earned_rewards: rewardMap,
});

const CollectionUnlockedEventV1Schema = z.strictObject({
  ...optionalSessionShape,
  event_type: z.literal("collection_unlocked"),
  collection_id: nonemptyString,
});

const CouponEarnedEventV1Schema = z.strictObject({
  ...optionalSessionShape,
  event_type: z.literal("coupon_earned"),
  coupon_id: nonemptyString,
});

export const LearningEventV1Schema = z.discriminatedUnion("event_type", [
  RunStartedEventV1Schema,
  AnswerSubmittedEventV1Schema,
  RunCompletedEventV1Schema,
  CollectionUnlockedEventV1Schema,
  CouponEarnedEventV1Schema,
]);

export type RunStartedEventV1 = z.infer<typeof RunStartedEventV1Schema>;
export type AnswerSubmittedEventV1 = z.infer<typeof AnswerSubmittedEventV1Schema>;
export type RunCompletedEventV1 = z.infer<typeof RunCompletedEventV1Schema>;
export type CollectionUnlockedEventV1 = z.infer<typeof CollectionUnlockedEventV1Schema>;
export type CouponEarnedEventV1 = z.infer<typeof CouponEarnedEventV1Schema>;
export type LearningEventV1 = z.infer<typeof LearningEventV1Schema>;
