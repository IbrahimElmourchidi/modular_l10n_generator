# Modular L10n docs

The documentation website for `modular_l10n_generator`, built with
[Starlight](https://starlight.astro.build). It is published to GitHub Pages by
`.github/workflows/docs.yml` on every push to `main` that changes `website/`.

```sh
npm install
npm run dev       # http://localhost:4321
npm run build     # static site in dist/
```

Pages are in `src/content/docs/`. Two kinds of content are generated; edit the
generators, not the output:

| Output | Generator |
|---|---|
| `src/content/docs/reference/commands.md` | `dart run tool/gen_commands_doc.dart` (from the package root) |
| `public/demos/*.gif`, `*.png` | `dart test tool/demos/record_test.dart`, then `node tool/demos/render.mjs` (needs Chrome and ffmpeg) |

Run both after changing a command's options or the terminal GUI.
