import { type FormEvent, useState } from "react";
import { Link, useSearchParams } from "react-router-dom";

import { useCloud } from "../cloud/cloud_provider";

function safeNext(raw: string | null): string {
  return raw?.startsWith("/") && !raw.startsWith("//") ? raw : "/dashboard";
}

function callbackUrl(next: string): string {
  const url = new URL(window.location.href);
  url.search = "";
  url.hash = `/auth/callback?next=${encodeURIComponent(next)}`;
  return url.toString();
}

export function LoginPage() {
  const cloud = useCloud();
  const [search] = useSearchParams();
  const [email, setEmail] = useState("");
  const [pending, setPending] = useState(false);
  const [status, setStatus] = useState<"idle" | "sent" | "error">("idle");
  const [message, setMessage] = useState("");

  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    if (!/^\S+@\S+\.\S+$/.test(email.trim())) {
      setStatus("error");
      setMessage("이메일 주소를 확인해 주세요.");
      return;
    }
    setPending(true);
    setStatus("idle");
    setMessage("");
    try {
      await cloud.sendMagicLink(email.trim(), callbackUrl(safeNext(search.get("next"))));
      setStatus("sent");
      setMessage("이메일을 확인해 주세요. 안전한 로그인 링크를 보냈습니다.");
    } catch {
      setStatus("error");
      setMessage("로그인 링크를 보내지 못했습니다. 잠시 후 다시 시도해 주세요.");
    } finally {
      setPending(false);
    }
  }

  return (
    <main id="main-content" className="auth-shell">
      <section className="auth-card" aria-labelledby="login-title">
        <Link className="back-link" to="/">← 처음으로</Link>
        <p className="eyebrow">보호자 전용</p>
        <h1 id="login-title">보호자 로그인</h1>
        <p>처음 오셨거나 다시 오신 보호자 모두, 이메일로 받은 한 번만 쓰는 링크로 시작합니다.</p>
        <form onSubmit={submit} noValidate>
          <label htmlFor="guardian-email">보호자 이메일</label>
          <input
            id="guardian-email"
            name="email"
            type="email"
            inputMode="email"
            autoComplete="email"
            value={email}
            onChange={(event) => setEmail(event.currentTarget.value)}
            aria-describedby="login-status"
            disabled={pending || status === "sent"}
          />
          <button className="primary-action button-reset" type="submit" disabled={pending || status === "sent"}>
            {pending ? "보내는 중…" : "로그인 링크 받기"}
          </button>
        </form>
        {message ? (
          <p id="login-status" role={status === "error" ? "alert" : "status"} tabIndex={-1}>
            {message}
          </p>
        ) : null}
      </section>
    </main>
  );
}
