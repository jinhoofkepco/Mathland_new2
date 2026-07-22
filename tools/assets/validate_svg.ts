import type { AssetIssue } from "./asset_schema.js";

const SAFE_ELEMENTS = new Set([
  "svg",
  "title",
  "desc",
  "g",
  "defs",
  "path",
  "rect",
  "circle",
  "ellipse",
  "line",
  "polyline",
  "polygon",
  "lineargradient",
  "radialgradient",
  "stop",
  "clippath",
  "mask",
  "use",
]);

export interface SvgValidationOptions {
  readonly expectedViewBox: string;
  readonly palette: readonly string[];
}

export function validateSvgText(
  svg: string,
  options: SvgValidationOptions,
): readonly AssetIssue[] {
  const issues: AssetIssue[] = [];
  const add = (code: string, message: string): void => {
    if (!issues.some((issue) => issue.code === code)) {
      issues.push({ code, path: [], message });
    }
  };

  if (/<!DOCTYPE\b|<!ENTITY\b/i.test(svg)) {
    add("SVG_DOCTYPE", "SVG document types and entities are forbidden");
  }
  if (/<\s*(?:[A-Za-z_][\w.-]*:)?script\b/i.test(svg)) {
    add("SVG_SCRIPT", "SVG scripts are forbidden");
  }
  if (/\s(?:[A-Za-z_][\w.-]*:)?on[a-z][\w.-]*\s*=/i.test(svg)) {
    add("SVG_EVENT_ATTRIBUTE", "SVG event attributes are forbidden");
  }
  if (/<\s*(?:[A-Za-z_][\w.-]*:)?image\b/i.test(svg) || /data:image\//i.test(svg)) {
    add("SVG_EMBEDDED_RASTER", "Embedded raster images are forbidden");
  }
  if (/<\s*(?:[A-Za-z_][\w.-]*:)?text\b/i.test(svg)) {
    add("SVG_RENDERED_TEXT", "Rendered SVG text is forbidden");
  }
  for (const match of svg.matchAll(/\b(?:href|xlink:href)\s*=\s*["']([^"']*)["']/gi)) {
    if (!/^#[A-Za-z_][\w.-]*$/.test((match[1] ?? "").trim())) {
      add("SVG_REMOTE_REFERENCE", "Only same-document fragment references are allowed");
    }
  }
  for (const match of svg.matchAll(/url\(\s*["']?([^)'"\s]+)["']?\s*\)/gi)) {
    if (!/^#[A-Za-z_][\w.-]*$/.test((match[1] ?? "").trim())) {
      add("SVG_REMOTE_REFERENCE", "Only same-document paint references are allowed");
    }
  }
  if (/@import\b/i.test(svg)) {
    add("SVG_REMOTE_REFERENCE", "Imported CSS references are forbidden");
  }
  if (/\sstyle\s*=/i.test(svg)) {
    add("SVG_INLINE_STYLE", "Inline style attributes are forbidden; use reviewed literal attributes");
  }

  const root = /<svg\b([^>]*)>/i.exec(svg);
  const viewBox = root ? /\bviewBox\s*=\s*["']([^"']+)["']/i.exec(root[1] ?? "")?.[1] : undefined;
  if (viewBox !== options.expectedViewBox) {
    add("SVG_VIEWBOX", `SVG viewBox must be ${options.expectedViewBox}`);
  }
  if (!/<title\b[^>]*\bid\s*=\s*["']title["'][^>]*>\s*[^<\s][^<]*<\/title>/i.test(svg)) {
    add("SVG_TITLE", "SVG requires a nonempty title#title");
  }
  if (!/<desc\b[^>]*\bid\s*=\s*["']desc["'][^>]*>\s*[^<\s][^<]*<\/desc>/i.test(svg)) {
    add("SVG_DESCRIPTION", "SVG requires a nonempty desc#desc");
  }
  if (!/\baria-labelledby\s*=\s*["']title desc["']/i.test(root?.[1] ?? "")) {
    add("SVG_ACCESSIBILITY", "SVG root must use aria-labelledby=\"title desc\"");
  }

  for (const match of svg.matchAll(/<\/?\s*([A-Za-z_][\w.-]*(?::[A-Za-z_][\w.-]*)?)/g)) {
    const element = (match[1] ?? "").split(":").at(-1)?.toLowerCase() ?? "";
    if (!SAFE_ELEMENTS.has(element)) {
      add("SVG_UNSAFE_ELEMENT", `SVG element <${element}> is not allowlisted`);
    }
  }

  const palette = new Set(options.palette.map((color) => color.toUpperCase()));
  for (const match of svg.matchAll(/\b(?:fill|stroke|stop-color|flood-color|color)\s*=\s*["']([^"']+)["']/gi)) {
    const value = (match[1] ?? "").trim();
    if (value === "none" || /^url\(#[A-Za-z_][\w.-]*\)$/.test(value)) {
      continue;
    }
    if (!/^#[A-Fa-f0-9]{6}$/.test(value) || !palette.has(value.toUpperCase())) {
      add("SVG_PALETTE", `SVG paint ${value} is outside the MathLand palette`);
    }
  }
  return issues;
}
