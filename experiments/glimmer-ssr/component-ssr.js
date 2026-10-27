import { Renderer, RootTemplate } from "@ember/-internals/glimmer";
import { run } from "@ember/runloop";
import {
  NodeDOMTreeConstruction,
  serializeBuilder,
} from "ember-source/@glimmer/node/index.js";
import createHTMLDocument from "ember-source/@simple-dom/document/index.js";

// Glimmer's non-browser URL adapter only reads the parsed protocol.
if (typeof globalThis.URL === "undefined") {
  globalThis.URL = {
    parse(value) {
      const normalized = value
        .replace(/^[\u0000-\u0020]+|[\u0000-\u0020]+$/g, "")
        .replace(/[\t\n\r]/g, "");
      const scheme = /^([a-z][a-z\d+.-]*:)/i.exec(normalized);
      return { protocol: scheme ? scheme[1].toLowerCase() : null };
    },
  };
}

const voidElements = new Set([
  "area",
  "base",
  "br",
  "col",
  "embed",
  "hr",
  "img",
  "input",
  "link",
  "meta",
  "param",
  "source",
  "track",
  "wbr",
]);

function escape(value) {
  return value
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;");
}

function serialize(node) {
  if (node.nodeType === -1) {
    return node.nodeValue;
  }
  if (node.nodeType === 3) {
    return escape(node.nodeValue);
  }
  if (node.nodeType === 8) {
    return `<!--${node.nodeValue}-->`;
  }
  const tag = node.nodeName.toLowerCase();
  const attributes = node.attributes
    .map((attribute) => ` ${attribute.name}="${escape(attribute.value)}"`)
    .join("");
  let html = `<${tag}${attributes}>`;
  if (voidElements.has(tag)) {
    return html;
  }
  for (let child = node.firstChild; child; child = child.nextSibling) {
    html += serialize(child);
  }
  return `${html}</${tag}>`;
}

export function renderToString(component, args) {
  const document = createHTMLDocument();
  const element = document.createElement("div");
  const renderer = new Renderer(
    { lookup() {} },
    document,
    { isInteractive: false, hasDOM: false },
    RootTemplate,
    {},
    (environment, cursor) => {
      environment.appendOperations = new NodeDOMTreeConstruction(document);
      return serializeBuilder(environment, cursor);
    }
  );
  try {
    run(() =>
      renderer.render(component, { into: { element, nextSibling: null }, args })
    );
    let html = "";
    for (let child = element.firstChild; child; child = child.nextSibling) {
      html += serialize(child);
    }
    return html;
  } finally {
    run(() => renderer.destroy());
  }
}
