import { render, screen } from "@testing-library/react";
import userEvent from "@testing-library/user-event";
import { MemoryRouter } from "react-router-dom";
import { describe, expect, it, vi } from "vitest";

import { CloudProvider } from "../cloud/cloud_provider";
import { FakeCloud } from "../cloud/fake_cloud";
import { LoginPage } from "./LoginPage";

class LoginCloud extends FakeCloud {
  readonly send = vi.fn(async (_email: string, _redirect: string) => undefined);

  override sendMagicLink(email: string, redirectTo: string): Promise<void> {
    return this.send(email, redirectTo);
  }
}

describe("LoginPage", () => {
  it("validates email accessibly before requesting a link", async () => {
    const cloud = new LoginCloud();
    render(
      <CloudProvider cloud={cloud}>
        <MemoryRouter>
          <LoginPage />
        </MemoryRouter>
      </CloudProvider>,
    );

    await userEvent.click(screen.getByRole("button", { name: "로그인 링크 받기" }));

    expect(await screen.findByRole("alert")).toHaveTextContent("이메일 주소를 확인해 주세요");
    expect(cloud.send).not.toHaveBeenCalled();
  });

  it("submits once and announces Korean success text", async () => {
    const cloud = new LoginCloud();
    render(
      <CloudProvider cloud={cloud}>
        <MemoryRouter initialEntries={["/login?next=%2Fdevices"]}>
          <LoginPage />
        </MemoryRouter>
      </CloudProvider>,
    );

    await userEvent.type(screen.getByLabelText("보호자 이메일"), "guardian@example.com");
    await userEvent.click(screen.getByRole("button", { name: "로그인 링크 받기" }));

    expect(await screen.findByRole("status")).toHaveTextContent("이메일을 확인해 주세요");
    expect(cloud.send).toHaveBeenCalledTimes(1);
    expect(cloud.send.mock.calls[0]?.[0]).toBe("guardian@example.com");
    expect(new URL(cloud.send.mock.calls[0]?.[1] ?? "https://invalid").origin).toBe(
      window.location.origin,
    );
  });
});
