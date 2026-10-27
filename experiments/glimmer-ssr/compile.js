import { precompile } from "ember-source/ember-template-compiler/index.js";

export function compile(source) {
  return precompile(source, {
    strictMode: true,
    plugins: {
      ast: [
        () => ({
          name: "escaped-blog-values",
          visitor: {
            MustacheStatement(node) {
              if (!node.escaped) {
                throw new Error(
                  "Unescaped expressions are unsupported; use the provided HTML fields"
                );
              }
            },
          },
        }),
      ],
    },
  });
}
