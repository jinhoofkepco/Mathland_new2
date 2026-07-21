import { StrictMode } from "react";
import { createRoot } from "react-dom/client";

import { App } from "./app/App";
import { MathLandRouter } from "./app/router";
import "./styles/tokens.css";
import "./styles/global.css";

const root = document.getElementById("root");

if (!root) {
  throw new Error("MathLand root element is missing");
}

createRoot(root).render(
  <StrictMode>
    <MathLandRouter>
      <App />
    </MathLandRouter>
  </StrictMode>,
);
