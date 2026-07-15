import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

test("exports the complete one-page service site", async () => {
  const html = await readFile(new URL("../out/index.html", import.meta.url), "utf8");

  assert.match(html, /<html lang="zh-CN">/);
  assert.match(html, /Windows 11 AI 编程环境急诊台/);
  assert.match(html, /只读体检/);
  assert.match(html, /标准搭建/);
  assert.match(html, /完整搭建/);
  assert.match(html, /平台资金托管/);
  assert.match(html, /不读取密钥内容/);
  assert.match(html, /匿名真实案例/);
  assert.match(html, /待手机端类目核验/);
  assert.doesNotMatch(html, /Your site is taking shape|Codex is working|react-loading-skeleton/);
});

test("ships the promised public downloads", async () => {
  await Promise.all([
    access(new URL("../out/downloads/audit.ps1", import.meta.url)),
    access(new URL("../out/downloads/client-intake.md", import.meta.url)),
    access(new URL("../out/downloads/service-guide.pdf", import.meta.url)),
    access(new URL("../out/downloads/SHA256SUMS.txt", import.meta.url)),
    access(new URL("../out/social-preview.png", import.meta.url)),
  ]);
});

test("publishes the exact audit script checksum", async () => {
  const [audit, sums] = await Promise.all([
    readFile(new URL("../out/downloads/audit.ps1", import.meta.url)),
    readFile(new URL("../out/downloads/SHA256SUMS.txt", import.meta.url), "utf8"),
  ]);
  const actual = createHash("sha256").update(audit).digest("hex");
  assert.equal(sums.trim(), `${actual}  audit.ps1`);
});

test("contains no obvious embedded credential", async () => {
  const [html, audit] = await Promise.all([
    readFile(new URL("../out/index.html", import.meta.url), "utf8"),
    readFile(new URL("../out/downloads/audit.ps1", import.meta.url), "utf8"),
  ]);
  const combined = html + audit;
  assert.doesNotMatch(combined, /\bsk-[A-Za-z0-9_-]{16,}\b/);
  assert.doesNotMatch(combined, /\bgh[pousr]_[A-Za-z0-9_]{16,}\b/);
});

test("keeps customer work outside the public build", async () => {
  await assert.rejects(access(new URL("../out/work", root)));
  await assert.rejects(access(new URL("../out/outputs", root)));
});
