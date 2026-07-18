import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

function cssRule(contents, selector) {
  const escaped = selector.replace(/[.*+?^${}()|[\]\\]/g, "\\$&");
  const match = new RegExp(`${escaped}\\s*\\{([^}]*)\\}`, "s").exec(contents);
  assert.ok(match, `missing CSS rule: ${selector}`);
  return match[1];
}

function cssToken(contents, name) {
  const match = new RegExp(`--${name}\\s*:\\s*(#[0-9a-f]{6})\\s*;`, "i").exec(contents);
  assert.ok(match, `missing CSS token: --${name}`);
  return match[1].toLowerCase();
}

function relativeLuminance(hex) {
  const channels = hex
    .slice(1)
    .match(/.{2}/g)
    .map((channel) => Number.parseInt(channel, 16) / 255)
    .map((channel) => (
      channel <= 0.04045
        ? channel / 12.92
        : ((channel + 0.055) / 1.055) ** 2.4
    ));

  return 0.2126 * channels[0] + 0.7152 * channels[1] + 0.0722 * channels[2];
}

function contrastRatio(first, second) {
  const [lighter, darker] = [relativeLuminance(first), relativeLuminance(second)]
    .sort((a, b) => b - a);
  return (lighter + 0.05) / (darker + 0.05);
}

test("uses sibling page landmarks and a focusable skip-link target", async () => {
  const html = await readFile(new URL("out/index.html", root), "utf8");
  const mainTags = html.match(/<main\b[^>]*>/g) ?? [];
  const targetIds = html.match(/\bid="main-content"/g) ?? [];

  assert.equal(mainTags.length, 1, "the document must contain exactly one main landmark");
  assert.equal(targetIds.length, 1, "the skip-link target id must be unique");
  assert.match(html, /<a class="skip-link" href="#main-content">/);
  assert.match(mainTags[0], /\bid="main-content"/);
  assert.match(mainTags[0], /\bclass="site-main"/);
  assert.match(mainTags[0], /\btabindex="-1"/);

  const skipIndex = html.indexOf('<a class="skip-link"');
  const headerIndex = html.indexOf('<header class="site-header"');
  const mainIndex = html.indexOf(mainTags[0]);
  const mainCloseIndex = html.indexOf("</main>", mainIndex);
  const footerIndex = html.indexOf("<footer", mainCloseIndex);

  assert.ok(skipIndex >= 0 && skipIndex < headerIndex, "skip link must precede the header");
  assert.ok(headerIndex < mainIndex, "header must be a sibling before main");
  assert.ok(mainIndex < mainCloseIndex, "main must have a closing tag");
  assert.ok(mainCloseIndex < footerIndex, "footer must be a sibling after main");

  const mainContents = html.slice(mainIndex, mainCloseIndex);
  assert.doesNotMatch(mainContents, /<header\b/);
  assert.doesNotMatch(mainContents, /<footer\b/);
  assert.doesNotMatch(html, /<div\b[^>]*class="hero-grid"[^>]*\bid="main-content"/);
});

test("keeps focus and primary text-link targets visibly operable", async () => {
  const css = await readFile(new URL("app/globals.css", root), "utf8");
  const linkFocus = cssRule(css, "a:focus-visible");
  const mainFocus = cssRule(css, ".site-main:focus");
  const navLink = cssRule(css, ".site-header nav a");
  const textLink = cssRule(css, ".text-link");

  assert.match(linkFocus, /outline:\s*3px solid var\(--amber\)\s*;/);
  assert.match(linkFocus, /outline-offset:\s*4px\s*;/);
  assert.match(mainFocus, /outline:\s*3px solid var\(--amber\)\s*;/);
  assert.match(navLink, /display:\s*inline-flex\s*;/);
  assert.match(navLink, /min-height:\s*44px\s*;/);
  assert.match(textLink, /display:\s*inline-flex\s*;/);
  assert.match(textLink, /min-height:\s*44px\s*;/);
  assert.match(textLink, /text-decoration:\s*underline\s*;/);
});

test("meets normal-text contrast on both light content surfaces", async () => {
  const css = await readFile(new URL("app/globals.css", root), "utf8");
  const colors = {
    "mint-dark": cssToken(css, "mint-dark"),
    muted: cssToken(css, "muted"),
  };
  const surfaces = [cssToken(css, "paper"), cssToken(css, "paper-2")];

  assert.equal(colors["mint-dark"], "#177355");
  assert.equal(colors.muted, "#596874");

  for (const [name, color] of Object.entries(colors)) {
    for (const surface of surfaces) {
      const ratio = contrastRatio(color, surface);
      assert.ok(
        ratio >= 4.5,
        `--${name} contrast on ${surface} is ${ratio.toFixed(3)}:1; expected at least 4.5:1`,
      );
    }
  }
});
