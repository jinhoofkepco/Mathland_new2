import {
  ANSWER_LAYOUT_IDS,
  EFFECT_PRESET_IDS,
  GENERATOR_IDS,
  ICON_IDS,
  MANIPULATIVE_IDS,
  SCENE_IDS,
} from "@mathland/contracts/content/ids";
import { useEffect, useState } from "react";

import type { ContentDraft } from "../cloud/cloud_port";

type PackageDraft = ContentDraft["package"];
type Band = PackageDraft["difficulty_bands"][number];
type ParameterValue = Band["generator_parameters"][string];
type Parameters = Band["generator_parameters"];

export interface ActivityFormProps {
  draft: PackageDraft;
  onChange(next: PackageDraft): void;
}

function JsonObjectEditor({
  label,
  value,
  onCommit,
}: {
  label: string;
  value: Parameters;
  onCommit(next: Parameters): void;
}) {
  const [text, setText] = useState(() => JSON.stringify(value, null, 2));
  const [error, setError] = useState("");
  useEffect(() => setText(JSON.stringify(value, null, 2)), [value]);

  function commit() {
    try {
      const parsed = JSON.parse(text) as unknown;
      if (parsed === null || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error();
      onCommit(parsed as Parameters);
      setError("");
    } catch {
      setError("JSON 객체 문법을 확인해 주세요.");
    }
  }

  return (
    <label>{label}
      <textarea className="code-input" value={text} onChange={(event) => setText(event.currentTarget.value)} onBlur={commit} />
      {error ? <small role="alert">{error}</small> : null}
    </label>
  );
}

function NumberParameter({ name, value, onChange }: { name: string; value: number; onChange(value: number): void }) {
  const [text, setText] = useState(String(value));
  useEffect(() => setText(String(value)), [value]);
  return (
    <label>{name}
      <input
        type="number"
        step="1"
        value={text}
        onChange={(event) => {
          const next = event.currentTarget.value;
          setText(next);
          if (/^-?(?:0|[1-9][0-9]*)$/u.test(next)) onChange(Number(next));
        }}
      />
    </label>
  );
}

function ArrayParameter({ name, value, onChange }: { name: string; value: number[]; onChange(value: number[]): void }) {
  const [text, setText] = useState(value.join(", "));
  const [error, setError] = useState("");
  useEffect(() => setText(value.join(", ")), [value]);
  function commit() {
    const parts = text.split(",").map((part) => part.trim()).filter(Boolean);
    const values = parts.map(Number);
    if (values.some((item) => !Number.isSafeInteger(item))) {
      setError("정수를 쉼표로 구분해 주세요.");
      return;
    }
    setError("");
    onChange(values);
  }
  return (
    <label>{name}
      <input value={text} onChange={(event) => setText(event.currentTarget.value)} onBlur={commit} />
      {error ? <small role="alert">{error}</small> : null}
    </label>
  );
}

function ParameterField({ name, value, onChange }: { name: string; value: ParameterValue; onChange(value: ParameterValue): void }) {
  if (typeof value === "boolean") {
    return <label className="checkbox-label"><input type="checkbox" checked={value} onChange={(event) => onChange(event.currentTarget.checked)} />{name}</label>;
  }
  if (typeof value === "number") return <NumberParameter name={name} value={value} onChange={onChange} />;
  if (Array.isArray(value)) return <ArrayParameter name={name} value={value} onChange={onChange} />;
  return <label>{name}<input value={value} onChange={(event) => onChange(event.currentTarget.value)} /></label>;
}

const EFFECT_LABELS: Record<keyof PackageDraft["run"]["effects"], string> = {
  correct: "정답 이펙트",
  wrong: "오답 이펙트",
  combo: "콤보 이펙트",
  boss: "보스 이펙트",
  level_up: "레벨업 이펙트",
  reward: "보상 이펙트",
  health_loss: "체력 감소 이펙트",
};

export function ActivityForm({ draft, onChange }: ActivityFormProps) {
  function update(mutator: (next: PackageDraft) => void) {
    const next = structuredClone(draft);
    mutator(next);
    onChange(next);
  }

  return (
    <div className="studio-form">
      <section className="studio-section field-grid">
        <h2>콘텐츠 식별</h2>
        <label>활동 ID<input value={draft.activity_id} readOnly /></label>
        <label>콘텐츠 버전<input value={draft.content_version} onChange={(event) => update((next) => { next.content_version = event.currentTarget.value; })} /></label>
        <label>아이콘
          <select value={draft.icon_id} onChange={(event) => update((next) => { next.icon_id = event.currentTarget.value as PackageDraft["icon_id"]; })}>
            {ICON_IDS.map((id) => <option key={id}>{id}</option>)}
          </select>
        </label>
        <label>게임 화면
          <select value={draft.scene_id} onChange={(event) => update((next) => { next.scene_id = event.currentTarget.value as PackageDraft["scene_id"]; })}>
            {SCENE_IDS.map((id) => <option key={id}>{id}</option>)}
          </select>
        </label>
      </section>

      <section className="studio-section">
        <h2>화면 문구</h2>
        <label>활동 제목
          <input value={draft.localizations["ko-KR"].title} onChange={(event) => update((next) => { next.localizations["ko-KR"].title = event.currentTarget.value; })} />
        </label>
        <label>활동 설명
          <textarea value={draft.localizations["ko-KR"].description} onChange={(event) => update((next) => { next.localizations["ko-KR"].description = event.currentTarget.value; })} />
        </label>
        <label>튜토리얼 단계 (한 줄에 하나)
          <textarea
            value={draft.localizations["ko-KR"].tutorial_steps.join("\n")}
            onChange={(event) => update((next) => {
              next.localizations["ko-KR"].tutorial_steps = event.currentTarget.value.split("\n").map((line) => line.trim()).filter(Boolean);
            })}
          />
        </label>
      </section>

      <section className="studio-section field-grid">
        <h2>게임 규칙</h2>
        <label>시작 체력
          <input type="number" value={draft.run.starting_hearts} readOnly aria-describedby="hearts-help" />
          <small id="hearts-help">오답 시 하나씩 줄어드는 3체력 규칙은 고정입니다.</small>
        </label>
        <label>완료 정답 수
          <input min={1} max={100} type="number" value={draft.run.goal.target} onChange={(event) => update((next) => { next.run.goal.target = Number(event.currentTarget.value); })} />
        </label>
        <label>정답 사과
          <input min={1} max={100} type="number" value={draft.run.rewards.apples_per_correct} onChange={(event) => update((next) => { next.run.rewards.apples_per_correct = Number(event.currentTarget.value); })} />
        </label>
        <label>완료 사과
          <input min={1} max={1000} type="number" value={draft.run.rewards.completion_apples} onChange={(event) => update((next) => { next.run.rewards.completion_apples = Number(event.currentTarget.value); })} />
        </label>
        <label className="checkbox-label"><input type="checkbox" checked={draft.run.timer.enabled} onChange={(event) => update((next) => { next.run.timer.enabled = event.currentTarget.checked; })} />시간 제한 사용</label>
        <label>제한 시간(초)
          <input min={1} max={3600} type="number" value={draft.run.timer.seconds} disabled={!draft.run.timer.enabled} onChange={(event) => update((next) => { next.run.timer.seconds = Number(event.currentTarget.value); })} />
        </label>
        <label className="checkbox-label"><input type="checkbox" checked={draft.run.timer.profile_can_disable} onChange={(event) => update((next) => { next.run.timer.profile_can_disable = event.currentTarget.checked; })} />아이 설정에서 시간 제한 해제 허용</label>
        <label>보스 등장 정답 수
          <input min={1} max={100} type="number" value={draft.run.boss_every_correct} onChange={(event) => update((next) => { next.run.boss_every_correct = Number(event.currentTarget.value); })} />
        </label>
        {draft.run.combo_thresholds.map((threshold, index) => (
          <label key={index}>콤보 {index + 1} 기준
            <input min={1} max={100} type="number" value={threshold} onChange={(event) => update((next) => { next.run.combo_thresholds[index] = Number(event.currentTarget.value); })} />
          </label>
        ))}
      </section>

      <section className="studio-section field-grid">
        <h2>버튼 반응과 이펙트</h2>
        {(Object.keys(EFFECT_LABELS) as Array<keyof typeof EFFECT_LABELS>).map((key) => (
          <label key={key}>{EFFECT_LABELS[key]}
            <select value={draft.run.effects[key]} onChange={(event) => update((next) => { next.run.effects[key] = event.currentTarget.value as PackageDraft["run"]["effects"][typeof key]; })}>
              {EFFECT_PRESET_IDS.map((id) => <option key={id}>{id}</option>)}
            </select>
          </label>
        ))}
      </section>

      <section className="studio-section">
        <h2>난이도 밴드</h2>
        <p>적응형 난이도는 아이 설정에서 켤 때만 이 범위 안에서 움직입니다. 기본값은 항상 꺼짐입니다.</p>
        <div className="band-grid">
          {draft.difficulty_bands.map((band, index) => (
            <article key={band.band_id} className="band-card">
              <h3>{band.band_id}</h3>
              <label>생성기
                <select value={band.generator_id} onChange={(event) => update((next) => { next.difficulty_bands[index]!.generator_id = event.currentTarget.value as Band["generator_id"]; })}>
                  {GENERATOR_IDS.map((id) => <option key={id}>{id}</option>)}
                </select>
              </label>
              <div className="parameter-grid">
                {Object.entries(band.generator_parameters).map(([name, value]) => (
                  <ParameterField key={name} name={name} value={value} onChange={(parameter) => update((next) => { next.difficulty_bands[index]!.generator_parameters[name] = parameter; })} />
                ))}
              </div>
              <details><summary>생성 파라미터 JSON</summary>
                <JsonObjectEditor label="전체 파라미터" value={band.generator_parameters} onCommit={(parameters) => update((next) => { next.difficulty_bands[index]!.generator_parameters = parameters; })} />
              </details>
              <label>정답 입력
                <select value={band.answer_layout.id} onChange={(event) => update((next) => { next.difficulty_bands[index]!.answer_layout.id = event.currentTarget.value as Band["answer_layout"]["id"]; })}>
                  {ANSWER_LAYOUT_IDS.map((id) => <option key={id}>{id}</option>)}
                </select>
              </label>
              <label>보조자료
                <select value={band.manipulative.id} onChange={(event) => update((next) => { next.difficulty_bands[index]!.manipulative.id = event.currentTarget.value as Band["manipulative"]["id"]; })}>
                  {MANIPULATIVE_IDS.map((id) => <option key={id}>{id}</option>)}
                </select>
              </label>
              <details><summary>보조자료 세부 설정</summary>
                <JsonObjectEditor label="구성" value={band.manipulative.config} onCommit={(parameters) => update((next) => { next.difficulty_bands[index]!.manipulative.config = parameters; })} />
                <JsonObjectEditor label="시작 상태" value={band.manipulative.initial_state} onCommit={(parameters) => update((next) => { next.difficulty_bands[index]!.manipulative.initial_state = parameters; })} />
              </details>
            </article>
          ))}
        </div>
      </section>

      {draft.adaptive_policy ? (
        <section className="studio-section field-grid">
          <h2>적응형 난이도 범위</h2>
          <label className="checkbox-label"><input aria-label="적응형 기본값" type="checkbox" checked={false} disabled />기본값 꺼짐 (아이 설정에서만 켬)</label>
          <label>판단 문제 수<input min={3} max={100} type="number" value={draft.adaptive_policy.window_size} onChange={(event) => update((next) => { if (next.adaptive_policy) next.adaptive_policy.window_size = Number(event.currentTarget.value); })} /></label>
          <label>상향 정답률<input min={0} max={1} step={0.05} type="number" value={draft.adaptive_policy.promote_correctness} onChange={(event) => update((next) => { if (next.adaptive_policy) next.adaptive_policy.promote_correctness = Number(event.currentTarget.value); })} /></label>
          <label>하향 정답률<input min={0} max={1} step={0.05} type="number" value={draft.adaptive_policy.demote_correctness} onChange={(event) => update((next) => { if (next.adaptive_policy) next.adaptive_policy.demote_correctness = Number(event.currentTarget.value); })} /></label>
          <label>최저 밴드
            <select value={draft.adaptive_policy.min_band_id} onChange={(event) => update((next) => { if (next.adaptive_policy) next.adaptive_policy.min_band_id = event.currentTarget.value; })}>
              {draft.difficulty_bands.map((band) => <option key={band.band_id}>{band.band_id}</option>)}
            </select>
          </label>
          <label>최고 밴드
            <select value={draft.adaptive_policy.max_band_id} onChange={(event) => update((next) => { if (next.adaptive_policy) next.adaptive_policy.max_band_id = event.currentTarget.value; })}>
              {draft.difficulty_bands.map((band) => <option key={band.band_id}>{band.band_id}</option>)}
            </select>
          </label>
        </section>
      ) : null}
    </div>
  );
}
