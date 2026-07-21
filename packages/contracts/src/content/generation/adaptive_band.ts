interface AdaptivePolicyInput {
  readonly min_band_id: string;
  readonly max_band_id: string;
  readonly window_size: number;
  readonly promote_correctness: number;
  readonly demote_correctness: number;
}

interface AdaptiveActivityInput {
  readonly activity_id?: unknown;
  readonly content_version?: unknown;
  readonly difficulty_bands?: readonly { readonly band_id?: unknown }[];
  readonly adaptive_policy?: AdaptivePolicyInput | undefined;
}

interface AnswerHistoryInput {
  readonly event_type?: unknown;
  readonly activity_id?: unknown;
  readonly content_version?: unknown;
  readonly sequence?: unknown;
  readonly question_seed?: unknown;
  readonly correctness?: unknown;
  readonly hints?: unknown;
}

const HINTED_ANSWER_PENALTY = 1.25;
const REPEATED_ERROR_PENALTY = 0.25;
const UINT32_MAX = 0xffff_ffff;

function isEligibleAnswer(
  event: AnswerHistoryInput,
  activityId: string,
  contentVersion: string,
): event is AnswerHistoryInput & {
  sequence: number;
  question_seed: number;
  correctness: boolean;
  hints: number;
} {
  return (
    event.event_type === "answer_submitted" &&
    event.activity_id === activityId &&
    event.content_version === contentVersion &&
    Number.isSafeInteger(event.sequence) &&
    (event.sequence as number) > 0 &&
    Number.isSafeInteger(event.question_seed) &&
    (event.question_seed as number) >= 0 &&
    (event.question_seed as number) <= UINT32_MAX &&
    typeof event.correctness === "boolean" &&
    Number.isSafeInteger(event.hints) &&
    (event.hints as number) >= 0
  );
}

export function selectAdaptiveBand(
  activity: AdaptiveActivityInput,
  fixedBandId: string,
  recentEvents: readonly AnswerHistoryInput[],
  enabled: boolean,
): string {
  if (!enabled || activity.adaptive_policy === undefined) return fixedBandId;

  const activityId = typeof activity.activity_id === "string" ? activity.activity_id : "";
  const contentVersion =
    typeof activity.content_version === "string" ? activity.content_version : "";
  const bandIds = (activity.difficulty_bands ?? [])
    .map((band) => band.band_id)
    .filter((bandId): bandId is string => typeof bandId === "string");
  const currentIndex = bandIds.indexOf(fixedBandId);
  const minimumIndex = bandIds.indexOf(activity.adaptive_policy.min_band_id);
  const maximumIndex = bandIds.indexOf(activity.adaptive_policy.max_band_id);
  const windowSize = activity.adaptive_policy.window_size;
  if (
    currentIndex < 0 ||
    minimumIndex < 0 ||
    maximumIndex < minimumIndex ||
    !Number.isSafeInteger(windowSize) ||
    windowSize < 1
  ) {
    return fixedBandId;
  }

  const eligible = recentEvents
    .filter((event) => isEligibleAnswer(event, activityId, contentVersion))
    .map((event) => ({ ...event }))
    .sort((left, right) => left.sequence - right.sequence);
  if (eligible.length < windowSize) return fixedBandId;
  const window = eligible.slice(-windowSize);

  let score = window.reduce((sum, event) => sum + (event.correctness ? 1 : 0), 0);
  score -= window.reduce(
    (sum, event) => sum + (event.hints > 0 ? HINTED_ANSWER_PENALTY : 0),
    0,
  );
  const seenIncorrectSeeds = new Set<number>();
  for (const event of window) {
    if (event.correctness) continue;
    if (seenIncorrectSeeds.has(event.question_seed)) score -= REPEATED_ERROR_PENALTY;
    seenIncorrectSeeds.add(event.question_seed);
  }
  const adjustedCorrectness = Math.max(0, Math.min(1, score / windowSize));

  const clampedCurrent = Math.max(minimumIndex, Math.min(maximumIndex, currentIndex));
  if (adjustedCorrectness >= activity.adaptive_policy.promote_correctness) {
    return bandIds[Math.min(maximumIndex, clampedCurrent + 1)] ?? fixedBandId;
  }
  if (adjustedCorrectness <= activity.adaptive_policy.demote_correctness) {
    return bandIds[Math.max(minimumIndex, clampedCurrent - 1)] ?? fixedBandId;
  }
  return bandIds[clampedCurrent] ?? fixedBandId;
}
