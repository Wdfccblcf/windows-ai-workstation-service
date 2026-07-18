import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";

const workflow = await readFile(
  new URL("../.github/workflows/pages.yml", import.meta.url),
  "utf8",
);

test("keeps the Pages build and deployment boundary auditable", () => {
  assert.match(workflow, /^name: Deploy Pages$/m);
  assert.match(workflow, /\n  push:\n    branches: \[main\]/);
  assert.match(workflow, /\n  pull_request:\n    branches: \[main\]/);
  assert.match(workflow, /\n  workflow_dispatch:\n/);
  assert.doesNotMatch(workflow, /pull_request_target/);
  assert.match(workflow, /\npermissions:\n  contents: read\n/);
  assert.doesNotMatch(workflow, /\bsecrets\b|\bPAT\b|api[_-]?key/i);

  assert.match(workflow, /uses: actions\/checkout@v6/);
  assert.match(workflow, /uses: actions\/setup-node@v6/);
  assert.match(workflow, /uses: actions\/configure-pages@v6/);
  assert.match(workflow, /uses: actions\/upload-pages-artifact@v5/);
  assert.match(workflow, /uses: actions\/deploy-pages@v5/);
  assert.match(workflow, /node-version: 22/);
  assert.match(
    workflow,
    /NEXT_PUBLIC_BASE_PATH: \/windows-ai-workstation-service/,
  );
  assert.match(workflow, /run: npm ci/);
  assert.match(workflow, /run: npm run check/);
  assert.match(workflow, /run: npm test/);
  assert.match(workflow, /path: \.\/out/);
  assert.doesNotMatch(workflow, /path: ['"]?\.(?:['"])?\s*$/m);

  const deployStart = workflow.indexOf("\n  deploy:\n");
  assert.ok(deployStart > 0, "deploy job must follow the build job");
  const buildJob = workflow.slice(workflow.indexOf("\n  build:\n"), deployStart);
  const deployJob = workflow.slice(deployStart);

  assert.doesNotMatch(buildJob, /pages: write|id-token: write/);
  assert.match(
    deployJob,
    /if: github\.ref == 'refs\/heads\/main' && github\.event_name != 'pull_request'/,
  );
  assert.match(deployJob, /\n    needs: build\n/);
  assert.match(deployJob, /\n    permissions:\n      pages: write\n      id-token: write\n/);
  assert.match(deployJob, /\n    environment:\n      name: github-pages\n/);
  assert.match(deployJob, /url: \$\{\{ steps\.deployment\.outputs\.page_url \}\}/);
  assert.doesNotMatch(deployJob, /actions\/checkout|npm (?:ci|test|run)/);

  assert.match(workflow, /format\('pr-\{0\}', github\.event\.pull_request\.number\)/);
  assert.match(workflow, /\|\| 'production'/);
  assert.match(workflow, /cancel-in-progress: false/);
});
