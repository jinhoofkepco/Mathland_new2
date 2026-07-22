import { type FormEvent, useState } from "react";
import { Navigate, useNavigate } from "react-router-dom";

import { useAuth } from "../auth/auth_provider";
import { useCloud } from "../cloud/cloud_provider";

function messageFor(error: unknown): string {
  return error instanceof Error && error.message.trim() !== ""
    ? "가족을 만들지 못했습니다. 잠시 후 다시 시도해 주세요."
    : "가족을 만들지 못했습니다.";
}

export function OnboardingPage() {
  const cloud = useCloud();
  const { state, refresh } = useAuth();
  const navigate = useNavigate();
  const [familyName, setFamilyName] = useState("");
  const [childNickname, setChildNickname] = useState("");
  const [pending, setPending] = useState(false);
  const [error, setError] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    const normalizedFamily = familyName.trim();
    const normalizedChild = childNickname.trim();
    if (normalizedFamily === "" || normalizedChild === "") {
      setError("가족 이름과 아이 별명을 입력해 주세요.");
      return;
    }
    setPending(true);
    setError("");
    try {
      await cloud.bootstrapGuardian({
        familyName: normalizedFamily,
        childNickname: normalizedChild,
      });
      await refresh();
      navigate("/devices", { replace: true });
    } catch (caught) {
      setError(messageFor(caught));
    } finally {
      setPending(false);
    }
  }

  if (state.status === "loading") {
    return <main className="state-page" aria-busy="true">처음 설정을 준비하고 있어요…</main>;
  }
  if (state.status === "error") {
    return <main className="state-page" role="alert">{state.message}</main>;
  }
  if (state.status === "signed_out") {
    return <Navigate to="/login?next=%2Fonboarding" replace />;
  }
  if (state.status === "authenticated" && state.familyStatus !== "onboarding") {
    if (state.familyStatus === "unauthorized") {
      return (
        <main className="state-page">
          <h1>가족 권한을 확인해 주세요</h1>
          <p>이미 가입된 계정의 권한은 관리자에게 문의해 주세요.</p>
        </main>
      );
    }
    return <Navigate to="/devices" replace />;
  }
  if (state.status === "unauthorized") {
    return (
      <main className="state-page">
        <h1>가족 권한을 확인해 주세요</h1>
        <p>이미 가입된 계정의 권한은 관리자에게 문의해 주세요.</p>
      </main>
    );
  }

  return (
    <main id="main-content" className="auth-shell">
      <section className="auth-card" aria-labelledby="onboarding-title">
        <p className="eyebrow">첫 1분 설정</p>
        <h1 id="onboarding-title">우리 가족 탐험 시작하기</h1>
        <p>가족과 아이를 한 번만 등록하면, 휴대폰의 MathLand를 바로 연결할 수 있어요.</p>
        <form onSubmit={submit} noValidate>
          <label htmlFor="family-name">가족 이름</label>
          <input
            id="family-name"
            autoComplete="organization"
            maxLength={80}
            value={familyName}
            onChange={(event) => setFamilyName(event.currentTarget.value)}
            disabled={pending}
          />
          <label htmlFor="child-nickname">아이 별명</label>
          <input
            id="child-nickname"
            autoComplete="off"
            maxLength={32}
            value={childNickname}
            onChange={(event) => setChildNickname(event.currentTarget.value)}
            disabled={pending}
          />
          <button className="primary-action button-reset" type="submit" disabled={pending}>
            {pending ? "가족을 만드는 중…" : "가족 만들고 기기 연결하기"}
          </button>
        </form>
        {error ? <p role="alert">{error}</p> : null}
        <p className="privacy-note">아이의 정확한 생일은 묻지 않으며, 별명만 저장합니다.</p>
      </section>
    </main>
  );
}
