import type { ValidationReportWire } from "../cloud/cloud_port";

type JsonRecord = Record<string, unknown>;

function record(value: unknown): JsonRecord {
  return value !== null && typeof value === "object" && !Array.isArray(value) ? value as JsonRecord : {};
}

function text(value: unknown, fallback = "알 수 없음"): string {
  return typeof value === "string" && value ? value : fallback;
}

function integer(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) ? value : null;
}

function answerText(value: unknown): string {
  const answer = record(value);
  if (answer.kind === "integer") return String(integer(answer.value) ?? "?");
  if (answer.kind === "integer_list" && Array.isArray(answer.values)) return answer.values.join(", ");
  return "?";
}

function previewCount(sample: JsonRecord): number {
  const manipulative = record(sample.manipulative);
  const state = record(manipulative.initial_state);
  const resolved = record(sample.resolved_parameters);
  for (const key of ["count", "value", "number", "target", "total"]) {
    const found = integer(state[key]) ?? integer(resolved[key]);
    if (found !== null) return found;
  }
  const answer = record(sample.correct_answer);
  return integer(answer.value) ?? 0;
}

function TenFrame({ count }: { count: number }) {
  const filled = Math.max(0, Math.min(10, count));
  return (
    <div className="ten-frame" role="img" aria-label={`10칸 중 ${filled}칸이 채워진 십틀`}>
      {Array.from({ length: 10 }, (_, index) => (
        <span key={index} className={index < filled ? "is-filled" : ""} data-testid={index < filled ? "ten-frame-filled" : undefined} />
      ))}
    </div>
  );
}

function Counters({ count }: { count: number }) {
  const visible = Math.max(0, Math.min(30, count));
  return (
    <div className="counter-preview" role="img" aria-label={`${count}개의 수 세기 칩`}>
      {Array.from({ length: visible }, (_, index) => <span key={index} />)}
      {count > visible ? <b>+{count - visible}</b> : null}
    </div>
  );
}

function BaseTen({ count }: { count: number }) {
  const safe = Math.max(0, Math.min(999, count));
  const hundreds = Math.floor(safe / 100);
  const tens = Math.floor((safe % 100) / 10);
  const ones = safe % 10;
  return (
    <div className="base-ten-preview" role="img" aria-label={`${safe}: 백판 ${hundreds}개, 십막대 ${tens}개, 낱개 ${ones}개`}>
      <div>{Array.from({ length: hundreds }, (_, index) => <span className="hundred-block" key={index} />)}</div>
      <div>{Array.from({ length: tens }, (_, index) => <span className="ten-rod" key={index} />)}</div>
      <div>{Array.from({ length: ones }, (_, index) => <span className="one-cube" key={index} />)}</div>
    </div>
  );
}

function NumberLine({ sample, count }: { sample: JsonRecord; count: number }) {
  const resolved = record(sample.resolved_parameters);
  const minimum = integer(resolved.min) ?? integer(resolved.start) ?? 0;
  const maximum = integer(resolved.max) ?? integer(resolved.end) ?? Math.max(10, count);
  return (
    <div className="number-line-preview" role="img" aria-label={`${minimum}부터 ${maximum}까지 수직선에서 ${count}`}>
      <span>{minimum}</span><i style={{ left: `${Math.max(0, Math.min(100, ((count - minimum) / Math.max(1, maximum - minimum)) * 100))}%` }} /><span>{maximum}</span>
    </div>
  );
}

function ManipulativePreview({ sample }: { sample: JsonRecord }) {
  const manipulative = record(sample.manipulative);
  const id = text(manipulative.id, "none");
  const count = previewCount(sample);
  if (id === "ten_frame") return <TenFrame count={count} />;
  if (id === "counters") return <Counters count={count} />;
  if (id === "base_ten") return <BaseTen count={count} />;
  if (id === "number_line") return <NumberLine sample={sample} count={count} />;
  return <p className="fine-print">보조자료 없음 · 수치 {count}</p>;
}

export function SamplePreview({ report }: { report: ValidationReportWire | null }) {
  if (!report?.samples.length) return null;
  return (
    <section className="studio-section sample-section">
      <h2>고정 시드 미리보기</h2>
      <p>각 난이도를 같은 시드로 다시 만들어 Godot 결과와 비교할 수 있습니다.</p>
      <div className="sample-grid">
        {report.samples.map((rawSample, index) => {
          const sample = record(rawSample);
          const band = text(sample.band_id);
          const generator = text(sample.generator_id);
          const seed = integer(sample.seed) ?? "?";
          return (
            <article key={`${band}-${seed}-${index}`}>
              <h3>{band} · {generator}</h3>
              <p>시드 {seed} · 정답 {answerText(sample.correct_answer)}</p>
              <ManipulativePreview sample={sample} />
              <details><summary>해결된 데이터</summary><pre>{JSON.stringify(sample, null, 2)}</pre></details>
            </article>
          );
        })}
      </div>
    </section>
  );
}
