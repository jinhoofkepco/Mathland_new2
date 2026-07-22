import { expect, test } from "@playwright/test";

async function expectNoHorizontalOverflow(page: import("@playwright/test").Page) {
  await expect
    .poll(() =>
      page.evaluate(() => ({
        viewport: document.documentElement.clientWidth,
        content: document.documentElement.scrollWidth,
      })),
    )
    .toEqual(expect.objectContaining({ content: expect.any(Number), viewport: expect.any(Number) }));
  const overflow = await page.evaluate(
    () => document.documentElement.scrollWidth - document.documentElement.clientWidth,
  );
  expect(overflow).toBeLessThanOrEqual(1);
}

test("opens the synthetic guardian dashboard and pairing journey", async ({ page }) => {
  await page.goto("./");
  await expect(page.getByRole("heading", { name: "MathLand 보호자" })).toBeVisible();

  await page.getByRole("link", { name: "샘플 현황 보기" }).click();
  await expect(page.getByRole("heading", { name: "데모 아이의 탐험 현황" })).toBeVisible();
  await expect(page.getByText("정답률")).toBeVisible();
  await expect(page.getByText("80%" , { exact: true })).toBeVisible();
  await expectNoHorizontalOverflow(page);

  await page.getByRole("link", { name: "기기 연결" }).click();
  await expect(page.getByRole("heading", { name: "기기 연결" })).toBeVisible();
  await page.getByRole("button", { name: "데모 아이 기기 연결" }).click();
  await expect(page.getByRole("dialog", { name: "데모 아이 기기 연결" })).toBeVisible();
  await expect(page.getByLabel(/연결 코드/)).toHaveText("482 913");
  await expectNoHorizontalOverflow(page);
});

test("opens the owner content studio without a desktop-only layout", async ({ page }) => {
  await page.goto("./#/dashboard");
  await expect(page.getByRole("heading", { name: "데모 아이의 탐험 현황" })).toBeVisible();

  await page.getByRole("link", { name: "콘텐츠 스튜디오" }).click();
  await expect(page.getByRole("heading", { name: "콘텐츠 스튜디오" })).toBeVisible();
  await expect(page.getByRole("heading", { name: "덧셈 탐험" })).toBeVisible();
  await page.getByRole("link", { name: "편집하기" }).click();
  await expect(page.getByRole("heading", { name: "덧셈 탐험 편집" })).toBeVisible();
  await page.getByLabel("완료 정답 수").fill("12");
  await expect(page.getByRole("button", { name: "초안 저장" })).toBeEnabled();
  await expectNoHorizontalOverflow(page);
});
