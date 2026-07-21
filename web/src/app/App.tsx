import { Link, Route, Routes } from "react-router-dom";

function WelcomePage() {
  return (
    <main id="main-content" className="welcome-shell">
      <section className="welcome-card" aria-labelledby="welcome-title">
        <div className="brand-mark" aria-hidden="true">
          <span className="brand-mark__ear brand-mark__ear--left" />
          <span className="brand-mark__ear brand-mark__ear--right" />
          <span className="brand-mark__face">⌣</span>
        </div>
        <p className="eyebrow">아이의 수학 탐험을 가까이에서</p>
        <h1 id="welcome-title">MathLand 보호자</h1>
        <p className="welcome-copy">
          학습 흐름을 확인하고, 난이도와 새 활동을 아이에게 맞게 조절하세요.
        </p>
        <Link className="primary-action" to="/login">
          이메일로 시작하기
          <span aria-hidden="true">→</span>
        </Link>
        <p className="privacy-note">아이의 플레이는 인터넷이 없어도 안전하게 이어집니다.</p>
      </section>
      <aside className="island-preview" aria-label="MathLand 탐험 안내">
        <span className="island-preview__sun" aria-hidden="true" />
        <div className="island-preview__content">
          <p>오늘의 탐험</p>
          <strong>수 감각 섬 · 3개 활동</strong>
          <div className="progress-track" aria-hidden="true">
            <span />
          </div>
        </div>
      </aside>
    </main>
  );
}

function LoginPlaceholder() {
  return (
    <main id="main-content" className="simple-page">
      <Link to="/">← 돌아가기</Link>
      <h1>보호자 로그인</h1>
      <p>안전한 이메일 링크로 로그인합니다.</p>
    </main>
  );
}

export function App() {
  return (
    <>
      <a className="skip-link" href="#main-content">
        본문으로 바로가기
      </a>
      <Routes>
        <Route path="/" element={<WelcomePage />} />
        <Route path="/login" element={<LoginPlaceholder />} />
      </Routes>
    </>
  );
}
