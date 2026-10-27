import fs from "node:fs";
import { createRequire } from "node:module";
import path from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";

// Run from frontend/discourse to reuse the host's exact Ember and build versions.
const require = createRequire(path.resolve("package.json"));
const { templateTag } = await import(
  pathToFileURL(require.resolve("@embroider/vite"))
);
const { build } = await import(pathToFileURL(require.resolve("rolldown")));
const { buildConfig } = await import(
  pathToFileURL(path.resolve("rolldown.config.mjs"))
);
const { default: maybeBabel } = await import(
  pathToFileURL(path.resolve("lib/maybe-babel.mjs"))
);
const directory = path.dirname(fileURLToPath(import.meta.url));
const outputDirectory = path.resolve(directory, "../../tmp/glimmer");
fs.mkdirSync(outputDirectory, { recursive: true });

for (const entry of ["render", "compile"]) {
  await build({
    input: path.join(directory, `${entry}.js`),
    platform: "node",
    resolve: buildConfig().resolve,
    moduleTypes: { ".gjs": "js" },
    plugins: [
      {
        name: "server-ember-imports",
        resolveId(source) {
          if (
            source.startsWith("@ember/") ||
            source.startsWith("ember-source/")
          ) {
            const name = source.replace(/^ember-source\//, "");
            const base = path.resolve(
              "node_modules/ember-source/dist/dev/packages",
              name
            );
            const resolved = [base, `${base}.js`, `${base}/index.js`].find(
              (candidate) =>
                fs.existsSync(candidate) && fs.statSync(candidate).isFile()
            );
            return resolved && fs.realpathSync(resolved);
          }
        },
      },
      templateTag(),
      maybeBabel({
        babelHelpers: "runtime",
        skipPreflightCheck: true,
        extensions: [".gjs", ".js", ".mjs"],
        babelrc: false,
      }),
    ],
    output: {
      file: path.join(outputDirectory, `${entry}.js`),
      format: "iife",
      name: "ComponentSSR",
      // Preserve module semantics for block-scoped functions inside MiniRacer scripts.
      intro: '"use strict";',
    },
  });
}

const { default: vm } = await import("node:vm");
const { createHash } = await import("node:crypto");
const compiler = fs.readFileSync(
  path.join(outputDirectory, "compile.js"),
  "utf8"
);
const runtime = fs.readFileSync(
  path.join(outputDirectory, "render.js"),
  "utf8"
);
const context = vm.createContext({});
vm.runInContext(compiler, context);
const templates = {};
for (const page of ["layout", "index", "article", "about", "not_found"]) {
  templates[page] = context.ComponentSSR.compile(
    fs.readFileSync(path.join(directory, "templates", `${page}.hbs`), "utf8")
  );
}
fs.writeFileSync(
  path.join(outputDirectory, "builtin.json"),
  JSON.stringify({
    version: createHash("sha256")
      .update(compiler + runtime)
      .digest("hex"),
    templates,
  })
);
