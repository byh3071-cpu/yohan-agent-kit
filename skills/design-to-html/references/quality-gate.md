# Quality Gate

Read this gate before implementation and before handoff. A handoff passes only when every applicable requirement has evidence in `design-qa.md`.

## Required checks

| Area | Requirement | Evidence |
| --- | --- | --- |
| Typography and contrast | Body text is 16px, secondary text is 14px, and text contrast meets WCAG AA. | Computed styles and contrast check |
| Responsive layout | Check 360, 432, 768, 1280, and 1440px for responsive behavior and horizontal overflow. At 432px, use a responsive layout; do not scale a desktop diagram. | Viewport captures and overflow result |
| Icons | Use a real icon library for icons. Do not use CSS art, handwritten SVG, or emoji substitutes. | Library and icon usage location |
| Interaction | Complete the full interaction path, including each introduced tab, menu, input, expand, and selection state. | Interaction checklist |
| Browser and keyboard | Record zero console errors and a keyboard path through the interactive controls. | Console output and keyboard steps |
| Visual QA | Compare the approved source and implementation in the same viewport and UI state; resolve P0 and P1 findings and record any P2 findings. | Side-by-side same-state captures and issue list |
| Preservation | Save the approved source and final evidence in project Git. | Tracked paths or stable refs |

## Handoff record

`design-qa.md` must include the required evidence and end with this literal line:

```text
final result: passed
```

Without that exact result, do not hand off the implementation.
