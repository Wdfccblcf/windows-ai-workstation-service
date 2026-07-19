import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { readFile } from "node:fs/promises";
import test from "node:test";

const root = new URL("../", import.meta.url);
const files = Object.fromEntries(
  await Promise.all(
    Object.entries({
      workflow: ".github/workflows/detector-release.yml",
      quality: ".github/workflows/quality.yml",
      prepare: "tools/prepare-detector-release.ps1",
      notes: "detector/releases/v1.0.2/RELEASE_NOTES.md",
      releaseJson: "detector/releases/v1.0.2/release.json",
      guide: "docs/detector-release.md",
      governance: "docs/repository-governance.md",
      readme: "README.md",
      zip: "public/downloads/windows-ai-detector-release-v1.0.2.zip",
      zipChecksum: "public/downloads/windows-ai-detector-release-v1.0.2.zip.sha256.txt",
      mainManifest: "public/downloads/SHA256SUMS.txt",
    }).map(async ([name, path]) => [
      name,
      await readFile(new URL(path, root)),
    ]),
  ),
);

const text = Object.fromEntries(
  Object.entries(files)
    .filter(([name]) => !["zip"].includes(name))
    .map(([name, contents]) => [name, contents.toString("utf8")]),
);
const releaseMetadata = JSON.parse(text.releaseJson);
const zipHash = createHash("sha256").update(files.zip).digest("hex");
const zipChecksumHash = createHash("sha256").update(files.zipChecksum).digest("hex");
const mainManifestHash = createHash("sha256").update(files.mainManifest).digest("hex");

function actionOwners(workflow) {
  return [...workflow.matchAll(/^\s*uses:\s+([^/\s]+)\/[^\s]+$/gm)]
    .map((match) => match[1]);
}

test("separates manual dry-run from tag-only publication", () => {
  assert.match(text.workflow, /push:\n    tags:\n      - "detector-v\*"/);
  assert.match(text.workflow, /workflow_dispatch:\n    inputs:\n      tag:/);
  assert.match(text.workflow, /default: "detector-v1\.0\.2"/);
  assert.match(
    text.workflow,
    /if: github\.event_name == 'push' && startsWith\(github\.ref, 'refs\/tags\/detector-v'\)/,
  );
  assert.match(
    text.workflow,
    /DETECTOR_TAG: \$\{\{ github\.event_name == 'workflow_dispatch' && inputs\.tag \|\| github\.ref_name \}\}/,
  );
  assert.doesNotMatch(text.workflow, /pull_request_target/);
  assert.doesNotMatch(text.workflow, /\$\{\{\s*inputs\.tag\s*\}\}[^\n]*run:/);
});

test("keeps write permissions inside the gated publish job", () => {
  assert.match(text.workflow, /\npermissions:\n  contents: read\n/);
  assert.match(
    text.workflow,
    /publish:\n    name: Attest and publish detector release[\s\S]*?permissions:\n      contents: write\n      id-token: write\n      attestations: write\n/,
  );
  assert.equal(text.workflow.match(/contents: write/g)?.length, 1);
  assert.equal(text.workflow.match(/id-token: write/g)?.length, 1);
  assert.equal(text.workflow.match(/attestations: write/g)?.length, 1);
  assert.deepEqual([...new Set(actionOwners(text.workflow))], ["actions"]);
  assert.doesNotMatch(text.workflow, /secrets\.|\bPAT\b|personal.access.token/i);
});

test("verifies exact bytes before attesting and publishing", () => {
  const verifyContract = text.workflow.indexOf("Verify detector release contract");
  const stageAssets = text.workflow.indexOf("Stage exact release assets");
  const attestZip = text.workflow.indexOf("Attest detector ZIP");
  const attestManifest = text.workflow.indexOf("Attest checksum manifest");
  const verifyAttestations = text.workflow.indexOf("Verify generated attestations");
  const publish = text.workflow.indexOf("Publish GitHub Release");
  assert.ok(verifyContract < stageAssets);
  assert.ok(stageAssets < attestZip);
  assert.ok(attestZip < attestManifest);
  assert.ok(attestManifest < verifyAttestations);
  assert.ok(verifyAttestations < publish);
  assert.equal(text.workflow.match(/uses: actions\/attest@v4/g)?.length, 2);
  assert.match(text.workflow, /gh attestation verify "release-assets\/\$ZIP_NAME"/);
  assert.match(text.workflow, /gh attestation verify release-assets\/SHA256SUMS\.txt/);
});

test("publishes only the five approved assets from a verified tag", () => {
  const publishBlock = text.workflow.slice(text.workflow.indexOf("gh release create"));
  assert.match(publishBlock, /--verify-tag/);
  assert.match(publishBlock, /--notes-file release-assets\/RELEASE_NOTES\.md/);
  for (const asset of [
    '"release-assets/$ZIP_NAME"',
    '"release-assets/$ZIP_NAME.sha256.txt"',
    "release-assets/SHA256SUMS.txt",
    "release-assets/release.json",
    "release-assets/PROVENANCE.md",
  ]) {
    assert.ok(publishBlock.includes(asset), `missing release asset: ${asset}`);
  }
  assert.doesNotMatch(publishBlock, /release-assets\/\*/);
  assert.equal(
    publishBlock.match(/release-assets\/RELEASE_NOTES\.md/g)?.length,
    1,
    "release notes must only be used as the body input",
  );
});

test("locks the PowerShell staging and version contract", () => {
  for (const boundary of [
    "Set-StrictMode -Version Latest",
    "^detector-v([0-9]+\\.[0-9]+\\.[0-9]+)$",
    "Output directory must be outside the repository.",
    "Output directory must be empty.",
    "Staged bytes differ",
    "release.json version does not match the tag.",
    "Main checksum file set differs.",
    "Main checksum manifest does not match audit.ps1.",
    "Standalone checksum does not match the detector ZIP.",
    "Main checksum manifest does not match the detector ZIP.",
  ]) {
    assert.ok(text.prepare.includes(boundary), `missing preparation boundary: ${boundary}`);
  }
  assert.doesNotMatch(text.prepare, /Invoke-WebRequest|Invoke-RestMethod|gh api|git tag|git push/);
  assert.match(text.quality, /Verify detector publication contract/);
  assert.match(text.quality, /tests\\detector-release-publication\.test\.ps1/);
});

test("keeps v1.0.2 bytes and component metadata unchanged", () => {
  assert.equal(releaseMetadata.version, "1.0.2");
  assert.equal(releaseMetadata.releaseType, "detection-only");
  assert.equal(releaseMetadata.repairIncluded, false);
  assert.equal(releaseMetadata.administratorPermissionRequested, false);
  assert.equal(
    zipHash,
    "7c8c3c5f0fa28daa90729808dd91bc6e4d3065ba79867f3968b6a303e883de80",
  );
  assert.equal(
    zipChecksumHash,
    "9362ed9823d07a056a4bca8e589751b97f2916132f686f5d0e49aa6d2cfe9e73",
  );
  assert.equal(
    mainManifestHash,
    "7b57e822b9c9e30ada0fbf6c86b4f785e42a7cdef1b6c3e4ec978d7e1576e03f",
  );
  assert.match(text.notes, new RegExp(zipHash));
});

test("documents verification, privacy, and forward-only correction", () => {
  for (const source of [text.notes, text.guide]) {
    assert.match(source, /gh attestation verify/);
    assert.match(source, /detection-only/);
    assert.match(source, /不.*管理员权限/);
    assert.match(source, /私密|private vulnerability report/);
  }
  assert.match(text.guide, /不得使用 `--force`/);
  assert.match(text.guide, /不移动或删除 tag/);
  assert.match(text.governance, /detector-v\*/);
  assert.match(text.readme, /docs\/detector-release\.md/);
});
