import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { access, readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

function parseChecksumManifest(contents, expectedNames) {
  const lines = contents.split(/\r?\n/);
  while (lines.at(-1) === "") {
    lines.pop();
  }

  assert.ok(lines.length > 0, "checksum manifest must not be empty");

  const entries = new Map();
  for (const [index, line] of lines.entries()) {
    assert.notEqual(line, "", `checksum manifest contains a blank line at ${index + 1}`);
    const match = /^([a-f0-9]{64}) {2}(.+)$/.exec(line);
    assert.ok(match, `invalid checksum line ${index + 1}: ${line}`);

    const [, hash, name] = match;
    assert.ok(!entries.has(name), `duplicate checksum entry: ${name}`);
    entries.set(name, hash);
  }

  assert.deepEqual([...entries.keys()].sort(), [...expectedNames].sort());
  return entries;
}

function sha256(contents) {
  return createHash("sha256").update(contents).digest("hex");
}

test("exports the complete one-page service site", async () => {
  const html = await readFile(new URL("../out/index.html", import.meta.url), "utf8");

  assert.match(html, /<html lang="zh-CN">/);
  assert.match(html, /Windows 11 AI 编程环境急诊台/);
  assert.match(html, /只读体检/);
  assert.match(html, /标准搭建/);
  assert.match(html, /完整搭建/);
  assert.match(html, /平台资金托管/);
  assert.match(html, /不读取密钥内容/);
  assert.match(html, /免费下载自动检测器/);
  assert.match(html, /19 项自动检测/);
  assert.match(html, /检测专用版不包含修复/);
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
    access(new URL("../out/downloads/windows-ai-detector-release-v1.0.2.zip", import.meta.url)),
    access(new URL("../out/downloads/windows-ai-detector-release-v1.0.2.zip.sha256.txt", import.meta.url)),
    access(new URL("../out/social-preview.png", import.meta.url)),
  ]);
});

test("publishes exact checksums for the audit script and detector", async () => {
  const detectorName = "windows-ai-detector-release-v1.0.2.zip";
  const [audit, detector, sums, detectorSum] = await Promise.all([
    readFile(new URL("../out/downloads/audit.ps1", import.meta.url)),
    readFile(new URL(`../out/downloads/${detectorName}`, import.meta.url)),
    readFile(new URL("../out/downloads/SHA256SUMS.txt", import.meta.url), "utf8"),
    readFile(new URL(`../out/downloads/${detectorName}.sha256.txt`, import.meta.url), "utf8"),
  ]);

  const manifest = parseChecksumManifest(sums, ["audit.ps1", detectorName]);
  const detectorManifest = parseChecksumManifest(detectorSum, [detectorName]);
  const auditHash = sha256(audit);
  const detectorHash = sha256(detector);

  assert.equal(manifest.get("audit.ps1"), auditHash);
  assert.equal(manifest.get(detectorName), detectorHash);
  assert.equal(detectorManifest.get(detectorName), detectorHash);
  assert.equal(detectorManifest.get(detectorName), manifest.get(detectorName));
});

test("parses checksum manifests across platforms and rejects unsafe entries", () => {
  const auditHash = "a".repeat(64);
  const detectorHash = "b".repeat(64);
  const expected = ["audit.ps1", "detector.zip"];
  const lf = `${auditHash}  audit.ps1\n${detectorHash}  detector.zip\n`;
  const crlf = lf.replaceAll("\n", "\r\n");

  assert.deepEqual(parseChecksumManifest(lf, expected), parseChecksumManifest(crlf, expected));
  assert.throws(
    () => parseChecksumManifest(`${lf}${auditHash}  audit.ps1\n`, expected),
    /duplicate checksum entry/,
  );
  assert.throws(() => parseChecksumManifest(`${auditHash}  audit.ps1\n`, expected));
  assert.throws(
    () => parseChecksumManifest(`${lf}${auditHash}  unexpected.txt\n`, expected),
  );
  assert.throws(
    () => parseChecksumManifest(`${auditHash} audit.ps1\n${detectorHash}  detector.zip\n`, expected),
    /invalid checksum line/,
  );
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
