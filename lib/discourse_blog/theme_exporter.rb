# frozen_string_literal: true

require "zip"

module ::DiscourseBlog
  class ThemeExporter
    def self.export(theme)
      files = {
        "blog-theme.json" =>
          JSON.pretty_generate(
            theme.slice("name", "accent_color", "paper_color", "ink_color").merge(
              "version" => 2,
              "template_engine" => GlimmerRenderer.enabled? ? "glimmer" : "liquid",
            ),
          ),
        "blog.css" => theme["css"],
        "blog.js" => theme["javascript"],
      }
      TemplateRenderer::PAGES.each do |page|
        extension = GlimmerRenderer.enabled? ? "hbs" : "liquid"
        files["templates/#{page}.#{extension}"] = theme["template_#{page}"]
      end

      Zip::OutputStream
        .write_buffer do |archive|
          files.each do |name, content|
            archive.put_next_entry(name)
            archive.write(content.to_s)
          end
        end
        .string
    end
  end
end
