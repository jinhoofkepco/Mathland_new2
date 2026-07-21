import { render, screen } from "@testing-library/react";
import { describe, expect, it } from "vitest";

import { SamplePreview } from "./SamplePreview";

describe("SamplePreview", () => {
  it("renders a numeric description and an accessible ten-frame preview", () => {
    render(<SamplePreview report={{
      valid: true,
      issues: [],
      samples: [{
        seed: 42,
        generator_id: "ten_frame_v1",
        band_id: "intro",
        prompt: { key: "count", args: { value: 7 } },
        correct_answer: { kind: "integer", value: 7 },
        manipulative: { id: "ten_frame", config: {}, initial_state: { count: 7 } },
        resolved_parameters: { value: 7 },
      }],
    }} />);

    expect(screen.getByRole("heading", { name: "intro · ten_frame_v1" })).toBeVisible();
    expect(screen.getByText("시드 42 · 정답 7")).toBeVisible();
    expect(screen.getByRole("img", { name: "10칸 중 7칸이 채워진 십틀" })).toBeVisible();
    expect(screen.getAllByTestId("ten-frame-filled")).toHaveLength(7);
  });
});
