import { setComponentTemplate } from "@ember/component";
import templateOnly from "@ember/component/template-only";
import { trustHTML } from "@ember/template";
import { createTemplateFactory } from "@ember/template-factory";
import { renderToString } from "./component-ssr";

const templates = new Map();

export function render(compiled, args) {
  let component = templates.get(compiled);
  if (!component) {
    component = setComponentTemplate(
      createTemplateFactory(JSON.parse(compiled)),
      templateOnly()
    );
    if (templates.size >= 64) {
      templates.delete(templates.keys().next().value);
    }
    templates.set(compiled, component);
  }
  // These fragments come only from server cooking or a previous template render.
  if (args.article) {
    args.article.body_html = trustHTML(args.article.body_html || "");
  }
  if (args.site) {
    args.site.about_html = trustHTML(args.site.about_html || "");
  }
  args.content_html = trustHTML(args.content_html || "");
  return renderToString(component, args);
}
