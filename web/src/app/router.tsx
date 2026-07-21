import type { PropsWithChildren } from "react";
import { HashRouter } from "react-router-dom";

export function MathLandRouter({ children }: PropsWithChildren) {
  return <HashRouter>{children}</HashRouter>;
}
