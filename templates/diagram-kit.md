# Diagram kit for briefings

The briefing template renders fenced `mermaid` blocks as diagrams and passes fenced `html` or `svg` blocks through as free-form drawings; scripts, embeds and event handlers are stripped. Pick the form that makes the slide's point fastest, and mix forms across slides.

| The slide shows | Draw it as |
|---|---|
| a process or request flow | a `mermaid` flowchart or sequence diagram |
| before and after, or who acts at each step | `.tracks` rows of `.step` pills |
| headline numbers | `.tiles` |
| the parts of a system and what each does | `.cards` |
| old and new structure side by side | `.compare` with `.before` and `.after` |
| components and links, or anything else | inline `<svg>`, or `.boxes` for a quick chain |

Colors come from the page tokens, so drawings follow the light and dark themes: `--accent` for new or highlighted things, `--signal` for human decisions and risks, `--ok` for done or verified, `--muted` and `--rule` for secondary lines. Keep one idea per drawing and about seven elements at most.

## Building blocks

Tiles (`em` colors the arrow):

```html
<div class="tiles">
  <div class="tile"><div class="num">11 <em>→</em> 4</div><div class="what">스킬</div><div class="how">rulebook · brief · mission · debrief</div></div>
</div>
```

Tracks (`human` marks a step a person decides; `new`, `done` and `warn` also exist):

```html
<div class="tracks">
  <div class="track"><div class="who">지금</div><div class="steps"><span class="step human">승인</span><span class="arrow">→</span><span class="step">구현</span></div><div class="count">사람 1단계</div></div>
</div>
```

Compare:

```html
<div class="compare">
  <div class="before"><h4>지금</h4><p>설명</p></div>
  <div class="after"><h4>바뀐 뒤</h4><p>설명</p></div>
</div>
```

Cards:

```html
<div class="cards">
  <div class="card"><b>/brief</b><p>구현 전 브리핑</p></div>
</div>
```

Boxes (`new` and `gone` mark added and removed parts):

```html
<div class="boxes"><span class="box">API</span><span class="arrow">→</span><span class="box new">Queue</span><span class="arrow">→</span><span class="box gone">Cron</span></div>
```

SVG: set a `viewBox`, color shapes with `style="fill: var(--accent-soft); stroke: var(--accent)"` (presentation attributes cannot read CSS variables), keep every label inside the viewBox, and keep text at 13px or larger.
