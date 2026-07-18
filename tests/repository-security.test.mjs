import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);

const [packageContents, quality, pages, security, governance, verifier] = await Promise.all([
  readFile(new URL("package.json", root), "utf8"),
  readFile(new URL(".github/workflows/quality.yml", root), "utf8"),
  readFile(new URL(".github/workflows/pages.yml", root), "utf8"),
  readFile(new URL("SECURITY.md", root), "utf8"),
  readFile(new URL("docs/repository-governance.md", root), "utf8"),
  readFile(new URL("tools/verify-repository-governance.ps1", root), "utf8"),
]);

const packageJson = JSON.parse(packageContents);

function actionOwners(workflow) {
  return [...workflow.matchAll(/^\s*uses:\s+([^/\s]+)\/[^\s]+$/gm)]
    .map((match) => match[1]);
}

test("pins the dependency audit command and fail threshold", () => {
  assert.equal(
    packageJson.scripts["audit:dependencies"],
    "npm audit --audit-level=high",
  );

  for (const workflow of [quality, pages]) {
    assert.doesNotMatch(workflow, /npm audit fix|--force/);
  }
});

test("runs the audit once in Quality and on every Pages build", () => {
  assert.match(
    quality,
    /- name: Audit production dependencies\n        if: runner\.os == 'Linux'\n        run: npm run audit:dependencies/,
  );
  assert.equal(
    quality.match(/run: npm run audit:dependencies/g)?.length,
    1,
  );

  assert.match(
    pages,
    /- name: Audit production dependencies\n        run: npm run audit:dependencies/,
  );
  assert.equal(
    pages.match(/run: npm run audit:dependencies/g)?.length,
    1,
  );
});

test("keeps workflows read-only and GitHub-owned", () => {
  for (const workflow of [quality, pages]) {
    assert.match(workflow, /\npermissions:\n  contents: read\n/);
    assert.doesNotMatch(workflow, /pull_request_target/);
    assert.deepEqual(
      [...new Set(actionOwners(workflow))],
      ["actions"],
      "every referenced Action must be owned by GitHub",
    );
  }
});

test("documents a usable private disclosure channel and governance contract", () => {
  assert.match(
    security,
    /https:\/\/github\.com\/Wdfccblcf\/windows-ai-workstation-service\/security\/advisories\/new/,
  );
  assert.match(security, /不要在公开 Issue、Pull Request 或讨论中披露漏洞细节/);

  for (const requiredCheck of [
    "Verify (ubuntu-latest)",
    "Verify (windows-latest)",
    "Build Pages artifact",
  ]) {
    assert.ok(governance.includes(requiredCheck));
  }

  for (const boundary of [
    "0 approvals",
    "GitHub-owned",
    "Dependabot alerts",
    "private vulnerability reporting",
    "逆序回滚",
  ]) {
    assert.ok(governance.includes(boundary), `missing governance boundary: ${boundary}`);
  }

  assert.match(verifier, /automated-security-fixes/);
  assert.match(verifier, /automated-security-fixes-disabled/);
  assert.match(verifier, /--paginate/);
  assert.doesNotMatch(verifier, /--slurp/);
  assert.match(verifier, /for \(\$attempt = 1; \$attempt -le 3; \$attempt\+\+\)/);
  assert.match(verifier, /Start-Sleep -Seconds 2/);
  assert.match(verifier, /Compare-Object[^\n]+-CaseSensitive/);
  assert.match(verifier, /bypass-pull-request-allowances-empty/);
  assert.match(verifier, /lock-branch-disabled/);
  assert.match(verifier, /push-restrictions-disabled/);
});

test("enforces the CodeQL default setup and zero-open-alert contract", () => {
  assert.match(verifier, /code-scanning\/default-setup/);
  assert.match(verifier, /code-scanning\/alerts\?state=open&per_page=100/);

  for (const target of [
    "configured",
    "actions",
    "javascript-typescript",
    "default",
    "remote",
    "standard",
  ]) {
    assert.ok(verifier.includes(`'${target}'`), `missing CodeQL target: ${target}`);
  }

  for (const checkName of [
    "codeql-default-setup-configured",
    "codeql-actions-language-enabled",
    "codeql-javascript-typescript-language-enabled",
    "codeql-query-suite-default",
    "codeql-threat-model-remote",
    "codeql-standard-runner",
    "code-scanning-open-alert-count-0",
  ]) {
    assert.ok(verifier.includes(checkName), `missing CodeQL check: ${checkName}`);
  }

  assert.match(verifier, /dependabot-open-alert-count-0/);
  assert.match(verifier, /IsNullOrWhiteSpace/);
  assert.doesNotMatch(verifier, /code-scanning[^\n]+(?:PATCH|dismiss|delete)/i);
});
