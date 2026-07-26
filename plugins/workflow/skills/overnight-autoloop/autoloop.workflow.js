export const meta = {
  name: 'overnight-autoloop',
  description: '무인 자율 결함루프: 감사발굴(+이월 주입)→수정(같은 파일 배칭)→검증+적대리뷰→PR(머지X), 아침 보고+이월 저장. args로 파라미터화.',
  phases: [
    { title: 'Discover', detail: '이전 run 이월분 주입 + 레포별 병렬 감사 → 결함 후보 → 같은 파일 배칭 그룹핑' },
    { title: 'Resolve', detail: '그룹(1~n결함)당: 진단→수정→검증→적대리뷰→PR/로컬커밋' },
    { title: 'Report', detail: '아침 머지권고 + park 보고 + 미시도 이월 저장' },
  ],
}

// ── testable helpers (Workflow 래퍼는 export const meta 만 허용 → 이름 있는 함수로 노출, 단위테스트가 소스에서 추출)
// @@HELPERS_BEGIN@@
/**
 * evidence 전체에서 경로처럼 생긴 토큰(+선택 :라인) 추출. 실패 시 null.
 * 우선순위: (1) ":라인" 붙은 경로형 — 실제 결함 위치는 거의 항상 :라인.
 *           (2) 없을 때만 강한 경로(슬래시+확장자). read/write·Node.js 산문은 제외 → title 폴백.
 * 루트 무확장자(Dockerfile/Makefile 등)는 :라인이 있을 때만 인정.
 * 드라이브 레터 보존. 백슬래시→슬래시, 소문자.
 */
function extractEvidenceLoc(evidence) {
  if (!evidence || typeof evidence !== 'string') return null
  const rootNoExt = 'Dockerfile|Makefile|Gemfile|Procfile|Jenkinsfile|Vagrantfile|Rakefile|Justfile|Taskfile|Brewfile'
  // (1순위) :라인 필수 — slash 경로 | name.ext(확장자 알파벳 시작 — v1.2·3.11 버전 제외) | 루트 무확장자
  const withLine = new RegExp(
    '((?:[A-Za-z]:[\\/\\\\])?(?:[A-Za-z0-9_\\-.]+[\\/\\\\])+[A-Za-z0-9_\\-.]+' +
      '|(?:[A-Za-z]:[\\/\\\\])?[A-Za-z0-9_\\-]+\\.[A-Za-z][A-Za-z0-9]{0,5}' +
      '|(?:' + rootNoExt + '))' +
      ':(\\d+)',
    'gi',
  )
  let m = withLine.exec(evidence)
  if (m) {
    return m[1].replace(/\\/g, '/').toLowerCase() + ':' + m[2]
  }
  // (2순위) :라인 없음 — 슬래시+확장자 둘 다 있는 강한 경로만 (read/write·node.js 제외)
  const strong = /((?:[A-Za-z]:[\/\\])?(?:[A-Za-z0-9_\-.]+[\/\\])+[A-Za-z0-9_\-.]+\.[A-Za-z0-9]{1,6})/g
  m = strong.exec(evidence)
  if (!m) return null
  return m[1].replace(/\\/g, '/').toLowerCase()
}
/** 발굴 dedup + 이월 preserve 공용 키. 위치(파일:라인) 우선, 없으면 title 폴백. 라인번호 절단 금지. */
function dedupKey(d) {
  const repo = (d && d.repo) || ''
  const loc = extractEvidenceLoc(d && d.evidence)
  if (loc) return repo + '|' + loc
  return repo + '|title:' + String((d && d.title) || '').toLowerCase().trim()
}
// @@HELPERS_END@@

// ── 파라미터(args) 검증 — SILENT FALLBACK 금지 (OS 원칙 1호) ─────────
// args = { scope:'audit'|'github'|'both', repos:[{name,path,kind:'python'|'next'}], capPRs:N,
//          deferredPath?:'<이월 json 절대경로>', resumeDeferred?:true|false (미전달=true, 문서화된 기본값) }
//
// [재발방지] 2026-07-01 밤샘 오실행: Workflow args 하네스 직렬화 버그로 args 가
// 스크립트에 미도달 → 조용히 하드코딩 기본레포(yohan-mcp/control-tower)로 폴백 →
// 엉뚱한 레포에 PR 6개 오생성(8.5h 무감지). 스크립트는 "사용자가 기본값 원함" vs
// "하네스가 args 드롭"을 구분할 수 없으므로 추측 금지 — 불완전 args 면 즉사.
// 기본값 해소는 스킬 런치층(SKILL.md)에서 명시적으로 하고 완전한 args 를 전달할 것.
const VALID_SCOPE = ['audit', 'github', 'both']
const VALID_KIND = ['python', 'next']
function die(msg) {
  throw new Error(
    `[overnight-autoloop] 파라미터 검증 실패 — ${msg}\n` +
    `무인 고비용 작업(PR 생성)이므로 불완전/미수신 args 에 기본값 폴백 금지(silent fallback 금지, 7/1 오실행 재발방지).\n` +
    `호출측이 { scope:'audit|github|both', repos:[{name,path,kind:'python|next'}], capPRs:양의정수 } 를 명시 전달해야 함 (+선택: deferredPath 절대경로 문자열, resumeDeferred 불리언).\n` +
    `받은 args = ${JSON.stringify(args)}`,
  )
}
// [2026-07-04] Workflow 런타임이 객체 args 를 JSON 문자열로 주입함(프로브 실증: typeof args==='string').
// 7/1 "args 미도달"의 실제 정체 = 미도달이 아니라 문자열 도달. 문자열이면 parse(실패 시 die — silent fallback 아님).
let cfg = args
if (typeof cfg === 'string') { try { cfg = JSON.parse(cfg) } catch (e) { die(`args 문자열 JSON.parse 실패: ${e.message}`) } }
if (!cfg || typeof cfg !== 'object' || Array.isArray(cfg)) die('args 객체 미수신 (Workflow args 직렬화 버그 의심 — 하네스가 스크립트에 args 를 전달했는지 먼저 확인)')
if (!VALID_SCOPE.includes(cfg.scope)) die(`scope 누락/무효 (받음=${JSON.stringify(cfg.scope)}, 허용=${VALID_SCOPE.join('|')})`)
if (!Array.isArray(cfg.repos) || cfg.repos.length === 0) die('repos 누락/빈배열 (대상 레포를 최소 1개 명시)')
cfg.repos.forEach((r, i) => {
  if (!r || typeof r !== 'object') die(`repos[${i}] 객체 아님 (받음=${JSON.stringify(r)})`)
  if (!r.name || typeof r.name !== 'string') die(`repos[${i}].name 누락/무효`)
  if (!r.path || typeof r.path !== 'string') die(`repos[${i}].path 누락/무효`)
  if (!VALID_KIND.includes(r.kind)) die(`repos[${i}].kind 무효 (받음=${JSON.stringify(r.kind)}, 허용=${VALID_KIND.join('|')})`)
  // vhk ADR-007: Workflow 자동 push/PR 오케스트레이션 금지 레포 — name·path 양쪽 차단(우회 방지)
  if (/^vhk$/i.test(r.name.trim()) || /[\\/]vhk[\\/]?$/i.test(r.path.trim())) {
    die(`repos[${i}]=vhk 금지 — vhk ADR-007 이 Workflow 자동 push 오케스트레이션을 금지한다 (vhk 는 수동 vhk-auto 계약 사용)`)
  }
})
if (!Number.isInteger(cfg.capPRs) || cfg.capPRs < 1) die(`capPRs 누락/무효 (받음=${JSON.stringify(cfg.capPRs)}, 양의 정수 필요)`)
// [2026-07-04] 이월(carry-over) 선택 파라미터 — 관용 처리(silent fallback 아님, 명시 기본값):
// - deferredPath: 미전달 = 이월 기능 전체 비활성(아래 로그 1줄로 명시). 전달 시 비어있지 않은 문자열(절대경로)이어야 함.
// - resumeDeferred: 미전달 = true(SKILL.md 에 문서화된 기본값). 전달 시 boolean. deferredPath 있을 때만 의미(주입 게이트).
//   비대칭 게이팅: 저장(이번 run 미시도 → 파일 overwrite)은 deferredPath 만 있으면 항상, 주입(이전 run 분 로드)만 resumeDeferred 로 제어.
if (cfg.deferredPath !== undefined && (typeof cfg.deferredPath !== 'string' || cfg.deferredPath.trim() === '')) die(`deferredPath 무효 (받음=${JSON.stringify(cfg.deferredPath)}, 비어있지 않은 절대경로 문자열 또는 미전달=이월 비활성)`)
if (cfg.resumeDeferred !== undefined && typeof cfg.resumeDeferred !== 'boolean') die(`resumeDeferred 무효 (받음=${JSON.stringify(cfg.resumeDeferred)}, true|false 또는 미전달=기본 true)`)

const REPOS = cfg.repos
const RESOLVE_CAP = cfg.capPRs
const SCOPE = cfg.scope
const DEFERRED_PATH = cfg.deferredPath === undefined ? '' : cfg.deferredPath.trim()
const RESUME_DEFERRED = cfg.resumeDeferred === undefined ? true : cfg.resumeDeferred
log(`[params ✓] scope=${SCOPE} · capPRs=${RESOLVE_CAP}(그룹=PR 단위) · repos=${REPOS.map((r) => `${r.name}(${r.kind})`).join(',')} · deferredPath=${DEFERRED_PATH || '(미전달)'} · resumeDeferred=${RESUME_DEFERRED}`)
if (!DEFERRED_PATH) log('[이월] deferredPath 미전달 — 이월 비활성(이전 run 주입·이번 run 저장 모두 안 함)')

function verifyCmd(r) {
  return r.kind === 'python'
    ? `cd ${r.path} && PYTHONPATH=${r.path} ${r.path}/.venv/Scripts/python.exe -m pytest -q`
    : `cd ${r.path} && npm run typecheck && npm run lint`
}
function repoOf(name) { return REPOS.find((x) => x.name === name) }

const ENV = `
[실행 환경]
대상 레포: ${REPOS.map((r) => `${r.name}(${r.kind})=${r.path}`).join(' · ')}
- 검증 커맨드: python=pytest(venv), next=typecheck+lint. 레포별: ${REPOS.map((r) => `[${r.name}] ${verifyCmd(r)}`).join(' | ')}
- 앱 도구 실행이 필요하면(예 get_context/status): scratchpad 에 .py 작성, load_dotenv 에 .env 절대경로 명시(없으면 의존백엔드 오폴백). 로컬 인프라: qdrant http://localhost:6333 · ollama http://localhost:11434(bge-m3).
`
const GITRULES = `
[GIT 규율 — 엄수]
- 시작: 해당 레포 cd, git checkout master(트리 더러우면 git checkout -- . 정리). 기본=master.
- 브랜치: git checkout -b <branchName>(있으면 checkout 후 이어서 amend).
- 커밋: git add -A && git commit, 메시지 한국어(간결·"왜" 중심). AI 흔적 금지 — 커밋 메시지에 Co-Authored-By·🤖·Claude 언급 넣지 마라.
- 커밋 후 검증: git log -1 --pretty=%B 출력에 co-authored·🤖·claude(대소문자 무시) 매치 시 git commit --amend 로 그 줄을 지우고 재확인(프롬프트 준수 실패 백스톱).
- 종료: 반드시 git checkout master(트리 clean).
[절대 금지] git merge · gh pr merge · git push --force · gh issue/pr close · 다른 브랜치 수정 · 외부 데이터스토어 재적재 · 노션 쓰기 · 커밋/PR에 AI 흔적(Co-Authored-By·🤖 Generated·Claude 언급).
`

const DEFECT_ITEM_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    repo: { type: 'string', description: 'REPOS 의 name 중 하나' },
    title: { type: 'string' },
    symptom: { type: 'string' },
    evidence: { type: 'string', description: '파일:라인 또는 실측 출력' },
    severity: { type: 'string', enum: ['high', 'med', 'low'] },
    fixable: { type: 'boolean', description: '경계 분명한 diff로 무인 수정+검증 가능' },
    rationale: { type: 'string', description: '왜 결함이며 기능/설계건이 아닌지' },
  },
  required: ['repo', 'title', 'symptom', 'evidence', 'severity', 'fixable', 'rationale'],
}
const DEFECTS_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: { defects: { type: 'array', items: DEFECT_ITEM_SCHEMA } },
  required: ['defects'],
}
// 이월 파일({savedAt, defects:[…]} 또는 최상위 배열) 로드/저장 — 파일 I/O 는 agent 위임(워크플로 샌드박스에 fs 없음)
const DEFERRED_LOAD_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    exists: { type: 'boolean', description: '파일이 존재하고 유효 JSON 이며 defects 를 얻었는가' },
    defects: { type: 'array', items: DEFECT_ITEM_SCHEMA },
    note: { type: 'string', description: '판정 요약(정상/없음/비어있음/parse 실패 사유)' },
  },
  required: ['exists', 'defects', 'note'],
}
const DEFERRED_SAVE_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    saved: { type: 'boolean' },
    count: { type: 'number', description: '저장 후 재독으로 확인한 defects 길이' },
    note: { type: 'string' },
  },
  required: ['saved', 'count', 'note'],
}
const SYNC_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    repo: { type: 'string', description: 'REPOS 의 name' },
    before: { type: 'string', description: 'fetch/merge 전 short SHA 또는 상태 요약' },
    after: { type: 'string', description: 'fetch/merge 후 short SHA 또는 상태 요약' },
    synced: { type: 'boolean', description: '원격 FF 반영 성공 여부' },
    note: { type: 'string', description: '스킵/실패 사유(dirty·FF 불가 등) 또는 성공 요약' },
  },
  required: ['repo', 'before', 'after', 'synced', 'note'],
}

// ── 배칭 헬퍼 (같은 파일 결함 그룹핑) ─────────────────────────────
// [재발방지] 2026-07-04 밤2 run: 같은 파일(studio_adapter.py)의 같은 호출부를 고치는 결함 2건
// (timeout·encoding)이 각각 PR(#31·#32)로 나가 두 번째가 리베이스 충돌. 같은 파일을 공유하는
// 결함은 1그룹=1브랜치=1PR 로 묶는다. 경로 추출은 보수적(확신 없으면 안 묶음):
// 코드 확장자 필수 + 디렉터리 없는 범용 파일명(index/main/route…)은 그룹핑 키에서 제외.
const PATH_EXT_RE = /[A-Za-z0-9_\-.\/\\]+\.(?:py|pyi|ts|tsx|js|jsx|mjs|cjs|json|ya?ml|toml|md|css|scss|vue|rs|go)\b/g
const GENERIC_BASENAMES = new Set(['index', 'main', 'app', 'utils', 'util', 'route', 'page', 'types', 'config', 'setup', 'test', 'tests', '__init__', 'mod', 'lib', 'readme'])
function extractGroupKeys(d) {
  const keys = new Set()
  for (const m of `${d.evidence || ''}\n${d.title || ''}`.matchAll(PATH_EXT_RE)) {
    const p = m[0].replace(/\\/g, '/').replace(/^\.?\//, '').toLowerCase()
    const base = p.slice(p.lastIndexOf('/') + 1)
    const stem = base.slice(0, base.lastIndexOf('.'))
    if (GENERIC_BASENAMES.has(stem)) {
      if (p.includes('/')) keys.add(`${d.repo}|${p}`) // 범용 이름은 전체 경로 완전일치만(디렉터리 없으면 불확실 → 키 제외)
    } else {
      keys.add(`${d.repo}|${base}`) // 고유 이름은 basename 일치(감사자마다 디렉터리 표기 유무가 달라서)
    }
  }
  // [과병합 가드, critic MAJOR 2026-07-05] 파일을 2개 이상 언급하는 "허브" 결함이 union-find
  // 이행병합으로 무관 그룹들을 하나로 흡수하던 결함(실증: X{a,b,c}+Y{b}+Z{c} → 1그룹 →
  // 난제 1건이 그룹 전체 PR 을 park). 다중 파일 결함은 그룹핑에서 제외(단독 처리) —
  // 원래 목적(같은 단일 파일을 고치는 결함 페어, #31·#32 케이스)만 묶는다.
  // 잔존 한계: 서로 다른 디렉터리의 동일 비범용 basename 은 여전히 오묶임 가능(SKILL.md Common Mistakes 참조).
  const arr = [...keys]
  return arr.length > 1 ? [] : arr
}
function groupDefects(list) {
  // union-find: 파일 키를 공유하는 결함을 이행적으로 병합. 루트=그룹 내 최소 인덱스(severity 정렬 순서 보존 → 그룹 대표=최고 우선순위).
  const parent = list.map((_, i) => i)
  const find = (x) => { while (parent[x] !== x) { parent[x] = parent[parent[x]]; x = parent[x] } return x }
  const union = (a, b) => { const ra = find(a), rb = find(b); if (ra !== rb) parent[Math.max(ra, rb)] = Math.min(ra, rb) }
  const owner = new Map()
  list.forEach((d, i) => {
    for (const k of extractGroupKeys(d)) {
      if (owner.has(k)) union(i, owner.get(k))
      else owner.set(k, i)
    }
  })
  const byRoot = new Map()
  list.forEach((d, i) => {
    const r = find(i)
    if (!byRoot.has(r)) byRoot.set(r, [])
    byRoot.get(r).push(d)
  })
  const groups = [...byRoot.keys()].sort((a, b) => a - b).map((r) => byRoot.get(r))
  groups.forEach((g, gi) => { if (g.length > 1) g.forEach((d) => { d.groupId = `g${gi + 1}` }) })
  return groups
}

// ── DISCOVER ────────────────────────────────────────────────────
const DISC = []
for (const r of REPOS) {
  DISC.push({ key: `${r.name}-correct`, prompt: `${ENV}\n[감사] ${r.name}(${r.kind}) 경로=${r.path} 핵심 로직 정확성 결함 사냥. 잘못된 계산/분기/None-safety/경계조건/계약위반을 실증거(파일:라인 + 실행출력)로. 기능/설계건·추측 제외.` })
  DISC.push({ key: `${r.name}-robust`, prompt: `${ENV}\n[감사] ${r.name} 견고성·데이터정합 결함. 조용한 에러삼킴(except: pass/빈폴백), 검증/스키마 누락, 설정정합(id·차원·키), 재시도/타임아웃 누락. 신규 건만, 실증거 필수.` })
}
if (REPOS.length > 1) {
  DISC.push({ key: 'cross', prompt: `${ENV}\n[감사] 레포 간 교차 정합 결함. 공유 스키마·벡터차원·임베딩모델·payload 키(쓰는쪽 vs 읽는쪽) 불일치 사냥. 실제 데이터와 코드 대조. 레포: ${REPOS.map((r) => r.name + ':' + r.path).join(', ')}` })
}
if (SCOPE === 'github' || SCOPE === 'both') {
  DISC.push({ key: 'github', prompt: `${ENV}\n[수집] 각 레포 'gh issue list --state open' 에서 무인 수정가능한 '버그/결함'만 추려라(대형기능·설계필요·중복 이슈 제외). 각 건을 fixable defect 로 변환. 레포: ${REPOS.map((r) => r.path).join(', ')}` })
}

phase('Discover')
// 이월 로드 — deferredPath 있으면 항상 읽는다(저장 시 미처리분 보존 판단에 필요).
// 주입(발굴 결과 선주입)만 resumeDeferred 로 제어 — 주입해야 발굴이 결정적이 된다
// (7/4 실측: run1 미시도 med 2건이 run2 에서 재발굴 안 되고 다른 결함이 나옴 → run 간 상태 필요).
let carried = []
if (DEFERRED_PATH) {
  const carry = await agent(
    `[이월 로드] 파일 ${DEFERRED_PATH} 를 읽어라(읽기 전용 — 파일 수정·삭제 금지). 이전 run 이 저장한 미시도(deferred) 결함 대기열이다.\n` +
    `- 파일 없음/빈 파일/JSON parse 실패 → exists=false, defects=[] (에러 아님 — 첫 run 일 수 있음. note 에 사유).\n` +
    `- 유효 JSON → 최상위 defects 배열(최상위가 그냥 배열이면 그 배열)을 가공·요약·번역 없이 그대로 defects 로 반환.`,
    { label: 'deferred:load', phase: 'Discover', schema: DEFERRED_LOAD_SCHEMA, effort: 'low' },
  )
  carried = carry && carry.exists && Array.isArray(carry.defects) ? carry.defects : []
  log(RESUME_DEFERRED
    ? `[이월 로드] ${DEFERRED_PATH} → ${carried.length}건 주입${carry && !carry.exists ? ` (파일 없음/무효: ${carry.note})` : ''}`
    : `[이월 로드] resumeDeferred=false — ${carried.length}건 로드만(주입 안 함, 저장 시 미처리분은 대기열 보존)`)
}
const carriedIn = RESUME_DEFERRED ? carried.length : 0 // 실제 주입된 수

// Discover 직전 원격 최신화 barrier — 낡은 스냅샷으로 이미 고친 결함을 재발굴하는 것 방지.
// 셸 없음 → agent 위임. reset --hard 금지; dirty/FF 불가면 건드리지 말고 note 보고.
const syncResults = await parallel(
  REPOS.map((r) => () => agent(
    `[동기화] 레포 ${r.name} 경로=${r.path}. 셸에서 다음만 수행하라:\n` +
    `1) cd "${r.path}"\n` +
    `2) git rev-parse --short HEAD 로 before 기록\n` +
    `3) git fetch origin\n` +
    `4) 현재 브랜치명 확인 후 git merge --ff-only origin/<현재브랜치> 시도\n` +
    `5) git rev-parse --short HEAD 로 after 기록\n` +
    `절대 금지: git reset --hard · git checkout --force · 임의 커밋 discard.\n` +
    `작업 트리 dirty(미커밋 변경)이거나 FF 불가(로컬 커밋/충돌)면 트리를 일절 건드리지 말고 synced=false + note 에 사유.\n` +
    `성공 시 synced=true. repo=${r.name}.`,
    { label: `sync:${r.name}`, phase: 'Discover', schema: SYNC_SCHEMA, effort: 'low' },
  )),
)
const syncFailed = []
for (const s of syncResults) {
  if (!s) {
    log('[동기화 경고] (무응답) — stale 스냅샷 위험, 해당 레포 발굴 신뢰도 하락')
    syncFailed.push('(무응답)')
    continue
  }
  log(`[동기화] ${s.repo}: synced=${s.synced} ${s.before}→${s.after}${s.note ? ` · ${s.note}` : ''}`)
  if (!s.synced) {
    log(`[동기화 경고] ${s.repo}: synced=false — stale 스냅샷 위험 (${s.note || '사유 미상'}). dirty/FF불가 skip 유지(파괴 금지).`)
    syncFailed.push(s.repo)
  }
}
if (syncFailed.length) log(`[동기화 경고] 실패 ${syncFailed.length}레포: ${syncFailed.join(', ')}`)

const discovered = await parallel(
  DISC.map((d) => () => agent(d.prompt, { label: `audit:${d.key}`, phase: 'Discover', schema: DEFECTS_SCHEMA, effort: 'high' })),
)
let all = []
for (const r of discovered) if (r && Array.isArray(r.defects)) all = all.concat(r.defects)
if (RESUME_DEFERRED && carried.length) all = carried.concat(all) // 선주입: 아래 dedup(seen)이 이월본을 우선 채택, 재발굴 중복은 버림(기존 로직 재사용)
const SEV = { high: 0, med: 1, low: 2 }
const seen = new Set()
const fixable = []
let dropNonFixable = 0
let dropUnknownRepo = 0
let dropDedup = 0
for (const d of all) {
  if (!d || !d.fixable) { dropNonFixable++; continue }
  if (!repoOf(d.repo)) { dropUnknownRepo++; continue }
  const k = dedupKey(d)
  if (seen.has(k)) { dropDedup++; continue }
  seen.add(k)
  fixable.push(d)
}
fixable.sort((a, b) => (SEV[a.severity] ?? 3) - (SEV[b.severity] ?? 3))
// 배칭: 같은 파일 공유 결함을 그룹핑한 뒤 capPRs 를 그룹(=브랜치=PR) 수 기준으로 컷 — capPRs 의 "PR 수" 의미 보존
const groups = groupDefects(fixable)
const toResolve = groups.slice(0, RESOLVE_CAP)
const deferred = groups.slice(RESOLVE_CAP).flat()
const dropped = all.length - fixable.length
log(`발굴 ${all.length}(이월 ${carriedIn} 포함) · 수정가능 ${fixable.length} · dropped ${dropped} (non-fixable ${dropNonFixable} · unknown-repo ${dropUnknownRepo} · dedup ${dropDedup}) · 그룹 ${groups.length}(배칭 ${groups.filter((g) => g.length > 1).length}) · 해결시도 ${toResolve.length}그룹/${toResolve.flat().length}건 · 보류 ${deferred.length}건`)

function branchFor(d, i) {
  const s = (d.title || 'fix').toLowerCase().replace(/[^a-z0-9]+/g, '-').replace(/(^-|-$)/g, '').slice(0, 28) || 'fix'
  return `auto-fix/${(repoOf(d.repo).name || 'repo').slice(0, 4)}-${i + 1}-${s}`
}

const FIX_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    status: { type: 'string', enum: ['fixed', 'cannot'] },
    branch: { type: 'string' },
    filesChanged: { type: 'array', items: { type: 'string' } },
    diffSummary: { type: 'string' },
    selfChecks: { type: 'string', description: '검증 실제 실행 결과 요약(통과/실패+핵심출력)' },
    committed: { type: 'boolean' },
    notes: { type: 'string' },
  },
  required: ['status', 'branch', 'committed', 'selfChecks', 'notes'],
}
const REVIEW_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    blocker: { type: 'boolean' },
    issues: { type: 'array', items: { type: 'object', additionalProperties: false, properties: { severity: { type: 'string' }, desc: { type: 'string' } }, required: ['severity', 'desc'] } },
    verdict: { type: 'string' },
  },
  required: ['blocker', 'issues', 'verdict'],
}
const FINAL_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: { pushed: { type: 'boolean' }, prUrl: { type: 'string' }, blockedReason: { type: 'string' } },
  required: ['pushed', 'prUrl', 'blockedReason'],
}

// ── RESOLVE (그룹당 순차 — 그룹=같은 파일 공유 결함 1~n건, 단일 브랜치·단일 PR) ──
phase('Resolve')
const results = []
for (let i = 0; i < toResolve.length; i++) {
  const g = toResolve[i]
  const d = g[0] // 그룹 대표 결함 = 그룹 내 최고 severity(정렬 순서 보존)
  const batched = g.length > 1
  const r = repoOf(d.repo)
  const branch = branchFor(d, i)
  const defectsBlock = batched
    ? `결함 그룹 ${g.length}건 — 같은 파일 공유(배칭). 이 브랜치 하나에서 전부 수정하고 PR 도 1개만 낸다(각 결함을 개별 진단하되 커밋은 이 브랜치에):\n${JSON.stringify(g)}`
    : `결함: ${JSON.stringify(d)}`
  log(`[해결 ${i + 1}/${toResolve.length}] ${d.repo}: ${batched ? `[배칭 ${g.length}건] ` : ''}${d.title}`)
  let attempt = 0, resolved = false, pushed = false, prUrl = '', parkReason = '', lastReview = '', lastSelf = '', prev = ''
  while (attempt < 3 && !resolved) {
    attempt++
    const fix = await agent(
      `${ENV}\n${GITRULES}\n[수정 ${attempt}/3] 레포=${d.repo} 경로=${r.path} 브랜치명=${branch} 검증=${verifyCmd(r)}\n${defectsBlock}\n${prev ? '직전 적대리뷰 피드백(반영): ' + prev : ''}\n근본원인 진단(증상패치 금지)→최소 diff 수정→검증 실제 실행→통과 시 로컬 커밋. ${batched ? `그룹 ${g.length}건 전부를 이 브랜치에서 해결·검증해야 fixed(오진으로 판명난 항목은 notes 에 근거 명시 시 제외 허용, 그 외 일부 미해결이면 status=cannot). ` : ''}실패면 status=cannot+사유. push/PR 은 금지(다음 단계).`,
      { label: `fix:${d.repo}#${i + 1}.${attempt}`, phase: 'Resolve', schema: FIX_SCHEMA, effort: 'high' },
    )
    if (!fix || fix.status !== 'fixed' || !fix.committed) {
      parkReason = fix ? `수정/검증 실패: ${fix.notes} | ${fix.selfChecks}` : 'fix agent 무응답'
      lastSelf = fix ? fix.selfChecks : ''
      continue
    }
    lastSelf = fix.selfChecks
    const rev = await agent(
      `${ENV}\n[적대 리뷰] 레포=${d.repo} 경로=${r.path} 브랜치=${branch}. git -C ${r.path} diff master...${branch} 를 적대적으로 검토. 결함 실제 해결·회귀·범위이탈·검증누락 점검.${batched ? ` 배칭 그룹 ${g.length}건: ${JSON.stringify(g.map((x) => x.title))} — 각 결함이 모두 실제 해결됐는지 개별 점검(오진 제외는 fix notes 근거 확인, 무근거 누락은 blocker).` : ''} 머지 막을 문제면 blocker=true. 읽기만(파일수정 금지).`,
      { label: `review:${d.repo}#${i + 1}.${attempt}`, phase: 'Resolve', schema: REVIEW_SCHEMA, effort: 'high' },
    )
    lastReview = rev ? rev.verdict : '리뷰 무응답'
    if (rev && !rev.blocker) {
      const fin = await agent(
        `${ENV}\n${GITRULES}\n[확정 push+PR] 레포=${d.repo} 경로=${r.path} 브랜치=${branch}. git push -u origin ${branch} 후 gh pr create --base master --head ${branch}(제목·본문 한국어, 본문에 ${batched ? `배칭 결함 ${g.length}건 각각의 요약·수정·검증결과` : '결함요약·수정·검증결과'}·"머지 금지: 사람 검토 대기"). PR 제목·본문에 AI 흔적(🤖·Claude·co-authored) 넣지 마라. 머지 절대 금지. push/gh 가 막히면 pushed=false·blockedReason 기록, 로컬커밋은 유지. 끝에 git checkout master.`,
        { label: `finalize:${d.repo}#${i + 1}`, phase: 'Resolve', schema: FINAL_SCHEMA, effort: 'medium' },
      )
      pushed = fin ? fin.pushed : false
      prUrl = fin ? fin.prUrl : ''
      if (fin && !fin.pushed) parkReason = `수정완료·로컬커밋, push/PR 차단: ${fin.blockedReason}`
      resolved = true
    } else {
      prev = rev ? JSON.stringify(rev.issues) : 'review blocker(미상)'
    }
  }
  results.push({
    repo: d.repo, title: batched ? `[배칭 ${g.length}건] ${d.title} 외` : d.title, titles: g.map((x) => x.title),
    severity: d.severity, branch, defects: g.length,
    outcome: resolved ? (pushed ? 'PR생성' : '로컬커밋(차단/대기)') : 'park(3회실패)',
    attempts: attempt, pushed, prUrl, parkReason, lastReview, lastSelf,
  })
}

// ── REPORT ──────────────────────────────────────────────────────
phase('Report')
// 이월 저장 — deferredPath 있으면 항상(resumeDeferred 와 무관): 이번 run 미시도만 남긴 최신 상태로
// 전체 overwrite(시도된 항목 제거, append 아님). report agent 보다 먼저 실행해 보고 실패에도 이월 상태는 남긴다.
let deferredSaveInfo = null
if (DEFERRED_PATH) {
  const pickDefect = ({ repo, title, symptom, evidence, severity, fixable, rationale }) => ({ repo, title, symptom, evidence, severity, fixable, rationale })
  // 이월분 중 이번 run 에서 처리 기회가 없었던 것은 대기열에 보존(조용한 유실 금지):
  // - repos 밖 레포의 이월분(주입돼도 시도 불가) — resumeDeferred 와 무관
  // - resumeDeferred=false 로 주입 자체가 안 된 이월분 — 단 이번 run 큐(시도+보류)와 중복(dedupKey)이면 새 것이 대표
  const runKeys = new Set(fixable.map(dedupKey))
  const preserved = carried.filter((c) => c && !runKeys.has(dedupKey(c)) && (!repoOf(c.repo) || !RESUME_DEFERRED))
  if (preserved.length) log(`[이월] 이번 run 에서 처리 기회 없던 이월분 ${preserved.length}건 → 대기열 보존(레포 밖 또는 미주입)`)
  const keep = deferred.map(pickDefect).concat(preserved.map(pickDefect))
  const save = await agent(
    `[이월 저장] 아래 json 코드블록 내용을 파일 ${DEFERRED_PATH} 에 그대로 저장하라(전체 overwrite — append 금지. 상위 디렉터리 없으면 생성. 내용 가공·요약·번역 금지). 이 파일은 다음 run 의 Discover 가 읽는 이월 대기열이며, 이번 run 에서 시도된 항목은 이미 제거된 최신 상태다.\n` +
    `저장 후 파일을 다시 읽어 defects 길이가 ${keep.length} 인지 확인하고 saved(성공여부)/count(재독 길이)/note 로 보고하라.\n` +
    `\`\`\`json\n${JSON.stringify({ savedAt: (typeof cfg.runStamp === 'string' && cfg.runStamp) || 'unstamped', defects: keep }, null, 2)}\n\`\`\``,
    { label: 'deferred:save', phase: 'Report', schema: DEFERRED_SAVE_SCHEMA, effort: 'low' },
  )
  const savedOk = !!(save && save.saved && save.count === keep.length)
  deferredSaveInfo = { path: DEFERRED_PATH, saved: savedOk, count: keep.length, note: save ? save.note : 'save agent 무응답' }
  log(`[이월 저장] ${DEFERRED_PATH} ← ${keep.length}건 ${savedOk ? '✓' : `✗ (${deferredSaveInfo.note}) — 아침에 반환 deferred 원본으로 수동 저장 필요`}`)
}
const REPORT_SCHEMA = {
  type: 'object', additionalProperties: false,
  properties: {
    headline: { type: 'string' },
    morning_report_md: { type: 'string', description: '아침 보고 두괄식 한국어 md: PR별 머지권고(권고/보류+근거)·park목록+사유·미시도 발굴목록·후속권고.' },
  },
  required: ['headline', 'morning_report_md'],
}
const report = await agent(
  `무인 자율 결함루프 결과를 아침 보고서(두괄식 한국어 md)로 합성. 머지 결정은 사람이 아침에 한다(밤=머지 0). PR별 머지권고·근거(배칭 PR 은 포함 결함 각각 명시), park 사유, 미시도 발굴목록, 이월 상태, **동기화 실패(stale) 레포** 포함. 과장 금지.\n\n해결(1행=1그룹=1브랜치/PR):\n${JSON.stringify(results)}\n\n미시도(보류):\n${JSON.stringify(deferred)}\n\n동기화 실패(synced=false/무응답, stale 위험): ${syncFailed.length ? syncFailed.join(', ') : '(없음)'}\n\n이월: 이전 run 주입 ${carriedIn}건 · ${deferredSaveInfo ? `대기열 ${deferredSaveInfo.count}건 → ${deferredSaveInfo.path} 저장 ${deferredSaveInfo.saved ? '성공' : `실패(${deferredSaveInfo.note})`}` : '비활성(deferredPath 미전달)'}\n\n전체 발굴=${all.length}`,
  { label: 'report', phase: 'Report', schema: REPORT_SCHEMA, effort: 'high' },
)

return {
  headline: report ? report.headline : '보고 합성 실패(report agent 무응답) — summary·results·deferred 원본으로 보고할 것',
  report_md: report ? report.morning_report_md : `# 아침 보고 합성 실패\n\nreport agent 가 결과를 반환하지 못함. 아래 원본 데이터로 수기 보고 필요.\n\n## results\n${JSON.stringify(results, null, 2)}\n\n## deferred\n${JSON.stringify(deferred, null, 2)}\n\n## syncFailed\n${JSON.stringify(syncFailed)}`,
  summary: {
    discovered: all.length, carriedIn, fixable: fixable.length,
    groups: groups.length, attempted: toResolve.length, // attempted = 시도한 그룹(=브랜치/PR 단위) 수
    prs: results.filter((x) => x.pushed).length,
    localOnly: results.filter((x) => x.outcome === '로컬커밋(차단/대기)').length,
    parked: results.filter((x) => x.outcome.startsWith('park')).length,
    syncFailed, // synced=false/무응답 레포 — stale 발굴 위험, 조용히 묻히지 않음
  },
  syncFailed, // 아침 보고·반환 최상위에도 명시
  deferredFile: deferredSaveInfo, // null=이월 비활성(deferredPath 미전달) · saved=false 면 아침에 deferred 원본으로 수동 저장
  results, deferred,
}
