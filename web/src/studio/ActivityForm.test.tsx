import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { describe, expect, it, vi } from "vitest";

import { ActivityForm } from "./ActivityForm";
import { studioPackageFixture } from "./studio_test_fixture";

describe("ActivityForm", () => {
  it("exposes allowlisted game, effect, band, and adaptive controls", async () => {
    const onChange = vi.fn();
    const draft = studioPackageFixture();
    render(<ActivityForm draft={draft} onChange={onChange} />);

    expect(screen.getByLabelText("콘텐츠 버전")).toHaveValue("1.0.0");
    expect(screen.getByLabelText("적응형 기본값")).not.toBeChecked();
    expect(screen.getByLabelText("적응형 기본값")).toBeDisabled();
    expect(screen.getAllByLabelText("생성기")).toHaveLength(3);
    expect(screen.getAllByLabelText("보조자료")).toHaveLength(3);
    expect(screen.getByLabelText("정답 이펙트")).toHaveValue("correct");

    await userEvent.selectOptions(screen.getAllByLabelText("보조자료")[0]!, "ten_frame");
    expect(onChange).toHaveBeenCalledOnce();
    expect(onChange.mock.calls[0]![0].difficulty_bands[0].manipulative.id).toBe("ten_frame");
  });

  it("edits numeric generator parameters without requiring raw JSON", async () => {
    const onChange = vi.fn();
    render(<ActivityForm draft={studioPackageFixture()} onChange={onChange} />);

    const maxima = screen.getAllByLabelText("operand_max");
    await userEvent.clear(maxima[0]!);
    await userEvent.type(maxima[0]!, "20");
    expect(onChange).toHaveBeenLastCalledWith(expect.objectContaining({
      difficulty_bands: expect.arrayContaining([
        expect.objectContaining({ generator_parameters: expect.objectContaining({ operand_max: 20 }) }),
      ]),
    }));
  });
});
