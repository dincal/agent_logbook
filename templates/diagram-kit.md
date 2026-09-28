# Diagram kit for briefings

Show with a picture whatever content a picture can show: numbers as tiles, steps as a track, old and new as a comparison, parts as cards, a chain as boxes, a structure as an SVG. There is no quota in either direction. A slide gets a picture because its content can be drawn, never to fill space, and content that no picture fits stays a table or text.

Two kinds of picture are never forced and never skipped:

- **Flowchart**: a briefing or debriefing always shows the main logic the change adds or alters, such as a business rule, a flow between systems, or state changes that move money or data. Draw it in domain steps, not function names, with about ten elements at most. A procedure that does not matter to the reader gets no flowchart.
- **ERD**: a briefing or debriefing always shows a database schema change as an ERD of the changed tables and relations. The project docs (`docs/system/data-model.md`) show every table in the database, split by domain when there are many. Files, documents and anything else that is not a database table never go into an ERD, and a change without a schema change gets no ERD and no filler line about it.

The briefing template renders fenced `mermaid` blocks as diagrams and passes fenced `html` or `svg` blocks through as free-form drawings; scripts, embeds and event handlers are stripped.

| The slide shows | Draw it as |
|---|---|
| important logic that changes | a `mermaid` flowchart or sequence diagram |
| a database schema change | a `mermaid` erDiagram of the changed tables |
| the whole database, in the project docs | `mermaid` erDiagrams that together show every table |
| before and after, or who acts at each step | `.tracks` rows of `.step` pills |
| headline numbers | `.tiles` |
| the parts of a system and what each does | `.cards` |
| old and new structure side by side | `.compare` with `.before` and `.after` |
| components and links, or anything else | inline `<svg>`, or `.boxes` for a quick chain |

Colors come from the page tokens, so drawings follow the light and dark themes: `--accent` for new or highlighted things, `--signal` for human decisions and risks, `--ok` for done or verified, `--muted` and `--rule` for secondary lines. Keep one idea per drawing and about seven elements at most. Labels follow `templates/writing.md`: plain words a reader outside the project understands.

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
