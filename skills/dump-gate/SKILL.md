---
name: dump-gate
description: >-
  Classifies long unrefined brain dumps before the prompt factory. Proposes
  interview vs factory vs chat. Triggers - long Korean monologue, 뇌덤프, 생각
  정리, 프롬프트로, ~했으면 좋겠다 dumps. Use proactively on long messy dumps.
---

# dump-gate

## When
Long unrefined owner text. Goal: avoid asking "프롬프트 만들어줘" every time.

## Steps
1. Classify **kind**: rumination | idea | plan_design | ui_design | impl_plan | research | debug | review | ops | content | decision | eval | automation
2. Score **quality**: solid | thin/abstract | unrealistic
3. Propose one line (unless session switch "충분하면 자동 공장" is on — still print kind+quality one line):
   - thin → `[인터뷰]` (interview-me)
   - solid → `[공장]` (thought-to-prompt 3-pass)
   - rumination → no factory; short clarify or `[인터뷰]`
4. Max **2** clarifying questions if needed

## Auto-factory switch
If owner enabled auto-factory and quality=solid → proceed to thought-to-prompt without waiting, but still show `kind=… quality=…`.
