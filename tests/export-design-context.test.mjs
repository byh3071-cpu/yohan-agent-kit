import { test } from 'node:test';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { createHash } from 'node:crypto';
import { mkdirSync, mkdtempSync, rmSync, writeFileSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { prepareBundle } from '../scripts/export-design-context.mjs';

const testsRoot = fileURLToPath(new URL('./.work/', import.meta.url));
function fixture(t) {
  mkdirSync(testsRoot, { recursive: true });
  const root = mkdtempSync(path.join(testsRoot, 'export-design-'));
  t.after(() => {
    assert.ok(path.resolve(root).startsWith(path.resolve(testsRoot) + path.sep));
    rmSync(root, { recursive: true, force: true });
  });
  const git = (...args) => execFileSync('git', ['-C', root, ...args], { windowsHide: true, stdio: ['ignore', 'pipe', 'pipe'] }).toString().trim();
  git('init', '-q');
  const pixels = Buffer.from('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a9qkAAAAASUVORK5CYII=', 'base64');
  writeFileSync(path.join(root, 'cover.png'), pixels);
  git('add', 'cover.png');
  git('-c', 'user.name=fixture', '-c', 'user.email=fixture@example.invalid', 'commit', '-qm', 'image fixture');
  const source = { repo: 'fixture', path: 'cover.png', gitRef: git('rev-parse', 'HEAD'), sha256: createHash('sha256').update(pixels).digest('hex') };
  const context = { schemaVersion: 1, projectId: 'fixture', references: [{ id: 'cover', media: ['instagram-thumbnail'], source, interpretationStatus: 'inferred', take: ['제목 크기 관계'], keep: ['이번 콘텐츠'], exclude: ['특정 색상'] }], taste: [] };
  const request = { schemaVersion: 1, workContext: { goal: 'fixture', nextGate: 'human choice' }, bundle: { medium: 'instagram-thumbnail', referenceIds: ['cover'], content: '같은 내용', canvas: '원본 크기', nextAction: '이미지를 비교' } };
  const resolution = { designContext: { contract: { ref: 'pinned' }, index: { ref: 'current' }, approvedSources: [], constraints: { newImageGeneration: false } } };
  const save = () => { writeFileSync(path.join(root, 'context.json'), JSON.stringify(context)); writeFileSync(path.join(root, 'request.json'), JSON.stringify(request)); };
  const run = () => { save(); return prepareBundle({ projectRoot: root, contextPath: 'context.json', requestPath: 'request.json', repositories: { fixture: root }, resolution }); };
  return { root, context, request, run, pixels };
}

test('exports only selected images with exact bytes, provenance, WorkContext and pending feedback', t => {
  const f = fixture(t);
  f.context.references.push({ id: 'unselected', source: { path: 'must-not-be-read' } });
  const result = f.run();
  assert.deepEqual(result.manifest.workContext, f.request.workContext);
  assert.equal(result.manifest.userReviewed, false);
  assert.equal(result.manifest.productionAuthorized, false);
  assert.equal(result.manifest.constraints.newImageGeneration, false);
  assert.match(result.files[0].bytes.toString(), /newImageGeneration: false/);
  assert.deepEqual(result.files.find(file => file.name === 'reference-01.png').bytes, f.pixels);
  assert.equal(result.manifest.references.length, 1);
  const feedback = JSON.parse(result.files.find(file => file.name === 'feedback-template.json').bytes);
  assert.equal(feedback.bundleId, result.manifest.bundleId);
  assert.equal(feedback.status, 'pending');
  assert.match(result.files[0].bytes.toString(), /AI 추론 · 미확정/);
  assert.match(result.files[0].bytes.toString(), /취향 없음/);
});

test('missing references remain missing and only the selected medium profile is exported', t => {
  const f = fixture(t);
  f.request.bundle.referenceIds = [];
  f.request.bundle.medium = 'instagram-highlight';
  const result = f.run();
  assert.equal(result.manifest.references.length, 0);
  assert.ok(result.manifest.missing.includes('선택한 레퍼런스 이미지 없음'));
  assert.match(result.files[0].bytes.toString(), /실제 원형 잘림/);
  assert.doesNotMatch(result.files[0].bytes.toString(), /76px|페이지 번호·CTA/);
});

test('rejects changed bytes, unknown references, wrong medium and unsupported approval claims', t => {
  const f = fixture(t);
  f.context.references[0].source.sha256 = '0'.repeat(64);
  assert.throws(f.run, /hash mismatch/);
  f.request.bundle.referenceIds = ['missing'];
  assert.throws(f.run, /resolve once/);
  f.request.bundle.referenceIds = ['cover']; f.request.bundle.medium = 'mova-ui';
  assert.throws(f.run, /outside this medium/);
  f.request.bundle.medium = 'instagram-thumbnail'; f.context.references[0].interpretationStatus = 'human-selected';
  assert.throws(f.run, /approval reference/);
});

test('conditional and inferred taste stay scoped; unapproved confirmed taste is refused', t => {
  const f = fixture(t);
  f.context.taste = [
    { state: 'conditional', rule: '이 시리즈에서만', scope: ['instagram-thumbnail'], evidence: 'project decision', condition: '해당 시리즈' },
    { state: 'inferred', rule: '미확정', scope: ['instagram-thumbnail'], evidence: 'observed image' },
    { state: 'confirmed', rule: '다른 매체', scope: ['mova-ui'], evidence: 'human', approvedBy: 'fixture' },
  ];
  const result = f.run();
  assert.equal(result.manifest.taste.length, 2);
  assert.deepEqual(result.manifest.taste.map(item => item.state), ['conditional', 'inferred']);
  f.context.taste.push({ state: 'confirmed', rule: '근거 없는 확정', scope: ['instagram-thumbnail'], evidence: 'agent guess' });
  assert.throws(f.run, /human approver/);
});
