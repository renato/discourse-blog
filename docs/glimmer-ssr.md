# Full-page Glimmer theme POC

This branch is a plugin-only experiment on SamSaffron/discourse-blog `master`.
It contains no reader-performance changes and requires no core changes.

## Run

With this plugin installed and core's frontend dependencies installed, build from
the core checkout:

```sh
pnpm --dir frontend/discourse exec node \
  ../../plugins/discourse-blog/experiments/glimmer-ssr/build.mjs
```

Start Rails with `BLOG_GLIMMER_SSR=1` in development. Production ignores the switch.
No URL flag is needed. The existing blog theme editor remains at
`/admin/plugins/discourse-blog/themes`. It displays Glimmer templates and inserts
Glimmer snippets through its existing variable picker.

The switch uses a separate theme store. Existing Liquid themes remain untouched;
disabling it restores the normal Liquid theme store. Liquid templates are not
translated automatically. Theme imports/exports declare `template_engine: glimmer`
and use `templates/*.hbs`; imports from the other engine are rejected.

## Save and serve

The five built-in templates—layout, index, article, about and not-found—are
precompiled during the build. All previously Liquid-rendered page content,
including navigation and footer, uses Glimmer. Rails still generates the HTML
head, metadata, asset tags, preview notices and discussion embed.

Saving a theme compiles its templates with the host's Ember compiler and stores
the artifacts alongside its source and revision. Invalid syntax, unresolved
components and unescaped expressions are rejected before writing the draft.
Unsaved previews compile through the same path. Activation snapshots both source
and artifacts; subsequent edits do not change the active theme.

Public requests only load and render artifacts. The compiler is a separate bundle
and is not loaded by readers. There is no source parsing, bundling, hydration,
Ember application boot, or additional browser JavaScript on a blog request.
The rendering VM still initializes its executable template representation on first use.

Templates use arguments such as `{{@site.title}}`, `{{@article.title}}` and
`{{#each @articles as |story|}}…{{/each}}`. Only server-provided cooked body,
about content and rendered layout content are marked as trusted HTML. Triple
mustaches are rejected. Arbitrary JavaScript, imports and browser components are
not supported. This does not enable event decorations or TOC.

## Prototype limits

Build artifacts are in ignored `tmp/glimmer/`. Build before starting Rails and
rebuild after changing Ember or renderer code. Artifacts carry a compiler/runtime
fingerprint; an incompatible saved theme falls back to the built-in templates
until it is saved and activated again. Missing build artifacts are an operator
error. Automatic deployment builds and upgrade migration are outside this POC.

Each Ruby process lazily creates separate, mutex-protected MiniRacer contexts for
compiling and rendering, with time/memory limits. The renderer uses private Ember
APIs, a simple DOM serializer and a bounded template cache. The generated script
preserves strict-mode module semantics. The protocol adapter normalizes ASCII
controls to prevent unsafe-link sanitization bypasses.

This is not a production-supported replacement or a speed optimization. No
concurrent-load or steady-state memory claim is made.

## Tests

```sh
bin/rspec plugins/discourse-blog/spec/requests/glimmer_article_spec.rb \
  plugins/discourse-blog/spec/requests/glimmer_themes_spec.rb \
  plugins/discourse-blog/spec/requests/blog_spec.rb \
  plugins/discourse-blog/spec/requests/themes_spec.rb
bin/qunit plugins/discourse-blog/test/javascripts/acceptance/blog-themes-test.js
```

Coverage includes all page types, compiled save/preview/activation, rendering when
the compiler file is absent, failed saves, Liquid-store isolation, escaping,
control-prefixed URLs, published snapshots, withdrawal, metadata/asset parity,
and Glimmer variable insertion in the editor.

Validated on 2026-10-27: 61 RSpec examples (seed 21859), 21 theme-editor QUnit
examples (seed dzd3epzg), and targeted Ruby/JavaScript lint passed. The baseline is
SamSaffron/discourse-blog `master` at `bbeb11f`.
