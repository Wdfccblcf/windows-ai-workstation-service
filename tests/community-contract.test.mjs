import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const privateReportPath =
  "/Wdfccblcf/windows-ai-workstation-service/security/advisories/new";
const paths = {
  contributing: "CONTRIBUTING.md",
  conduct: "CODE_OF_CONDUCT.md",
  optimization: ".github/ISSUE_TEMPLATE/optimization.yml",
  bug: ".github/ISSUE_TEMPLATE/bug.yml",
  config: ".github/ISSUE_TEMPLATE/config.yml",
  pullRequest: ".github/pull_request_template.md",
};

const entries = await Promise.all(
  Object.entries(paths).map(async ([name, path]) => [
    name,
    await readFile(new URL(path, root), "utf8"),
  ]),
);
const files = Object.fromEntries(entries);
const optimization = JSON.parse(files.optimization);
const bug = JSON.parse(files.bug);
const config = JSON.parse(files.config);

function formFields(form) {
  return new Map(
    form.body
      .filter((item) => item.id)
      .map((item) => [item.id, item]),
  );
}

function assertPrivateReport(value) {
  const report = new URL(value);
  assert.equal(report.protocol, "https:");
  assert.equal(report.hostname, "github.com");
  assert.equal(report.pathname, privateReportPath);
  assert.equal(report.search, "");
  assert.equal(report.hash, "");
}

function assertRequiredForm(form, expectedIds) {
  assert.equal(typeof form.name, "string");
  assert.equal(typeof form.description, "string");
  assert.ok(Array.isArray(form.body));

  const fields = formFields(form);
  assert.deepEqual([...fields.keys()], expectedIds);
  for (const field of fields.values()) {
    assert.equal(field.validations?.required, true, `${field.id} must be required`);
  }

  const privacy = fields.get("privacy");
  assert.equal(privacy.type, "checkboxes");
  assert.ok(privacy.attributes.options.length >= 2);
  assert.ok(privacy.attributes.options.every((option) => option.required === true));
}

test("ships strict optimization and bug issue forms", () => {
  assertRequiredForm(optimization, [
    "baseline",
    "reason",
    "scope",
    "non_goals",
    "plan",
    "acceptance",
    "rollback",
    "privacy",
  ]);
  assertRequiredForm(bug, [
    "reproduction",
    "expected",
    "actual",
    "environment",
    "evidence",
    "impact",
    "acceptance",
    "rollback",
    "privacy",
  ]);

  assert.match(JSON.stringify(optimization), /Issue → Spec PR → Impl PR/);
  assert.match(JSON.stringify(bug), /脱敏/);
});

test("disables blank issues and routes sensitive reports privately", () => {
  assert.equal(config.blank_issues_enabled, false);
  assert.equal(config.contact_links.length, 1);
  assertPrivateReport(config.contact_links[0].url);
  assert.match(config.contact_links[0].about, /不要公开敏感信息/);
});

test("documents the full issue, spec, implementation, and evidence sequence", () => {
  for (const term of [
    "Issue → Spec PR → Impl PR → evidence/close",
    "origin/main",
    "固定 final head SHA",
    "禁止 bypass",
    "45 项 PASS",
  ]) {
    assert.ok(files.contributing.includes(term), `missing contribution term: ${term}`);
  }

  for (const term of [
    "Linked Issue",
    "Linked Spec",
    "为什么改",
    "Plan / implementation",
    "Fresh install / fresh clone",
    "安全、隐私与发布影响",
    "SHA256",
    "风险与回滚",
    "固定 final head",
  ]) {
    assert.ok(files.pullRequest.includes(term), `missing PR term: ${term}`);
  }
});

test("uses the recognized covenant with a private enforcement path", () => {
  assert.match(files.conduct, /^# Contributor Covenant Code of Conduct$/m);

  const inlineLinks = [...files.conduct.matchAll(/\]\((https:\/\/[^)\s]+)\)/g)].map(
    ([, href]) => href,
  );
  const conductLink = inlineLinks.find((href) => {
    const candidate = new URL(href);
    return candidate.hostname === "github.com" && candidate.pathname === privateReportPath;
  });
  assert.ok(conductLink, "missing private Conduct report link");
  assertPrivateReport(conductLink);
  assert.ok(files.conduct.includes("[Conduct]"));
  assert.ok(files.conduct.includes("version 2.0"));
  assert.doesNotMatch(files.conduct, /\[INSERT CONTACT METHOD\]/);
});

test("keeps every public contribution entry privacy aware", () => {
  const combined = Object.values(files).join("\n");
  for (const warning of ["API Key", "token", "客户数据", "完整用户路径", "私密报告"]) {
    assert.ok(combined.includes(warning), `missing privacy warning: ${warning}`);
  }

  assert.doesNotMatch(combined, /AKIA[0-9A-Z]{16}/);
  assert.doesNotMatch(combined, /sk-[A-Za-z0-9_-]{20,}/);
  assert.doesNotMatch(combined, /C:\\Users\\[^<\s]+/i);
});
