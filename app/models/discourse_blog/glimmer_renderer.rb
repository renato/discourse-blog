# frozen_string_literal: true

module ::DiscourseBlog
  class GlimmerRenderer
    ROOT = Pathname.new(__dir__).join("../../../experiments/glimmer-ssr")
    BUILD = ROOT.join("../../tmp/glimmer")
    LOCK = Mutex.new

    def self.enabled?
      Rails.env.local? && ENV["BLOG_GLIMMER_SSR"] == "1"
    end

    def self.builtin(page)
      raise ArgumentError if TemplateRenderer::PAGES.exclude?(page)
      ROOT.join("templates/#{page}.hbs").read
    end

    def self.compile_theme(values)
      artifacts = bundle
      templates =
        TemplateRenderer::PAGES.to_h do |page|
          source = values["template_#{page}"]
          unless source.is_a?(String) && source.valid_encoding? &&
                   source.bytesize <= TemplateRenderer::MAX_TEMPLATE_BYTES
            raise Discourse::InvalidParameters.new(I18n.t("discourse_blog.themes.template_invalid"))
          end
          compiled =
            (
              if source.present?
                call("compile", "compile", source)
              else
                artifacts.fetch("templates").fetch(page)
              end
            )
          [page, compiled]
        rescue MiniRacer::Error => error
          raise Discourse::InvalidParameters.new(
                  I18n.t(
                    "discourse_blog.themes.template_parse_error",
                    error: "#{page}: #{error.message}",
                  ),
                )
        end
      { "version" => artifacts.fetch("version"), "templates" => templates }
    end

    def self.render(page, assigns, theme:, custom: true, **)
      artifacts = bundle
      compiled = theme["glimmer"] if custom
      compiled = artifacts unless compiled && compiled["version"] == artifacts["version"]
      call("render", "render", compiled.fetch("templates").fetch(page), assigns)
    end

    def self.bundle
      JSON.parse(BUILD.join("builtin.json").read)
    end

    def self.call(kind, method, *arguments)
      raise Discourse::InvalidAccess unless enabled?
      LOCK.synchronize do
        file = BUILD.join("#{kind}.js")
        version = [Process.pid, file.mtime.to_f, file.size]
        @contexts ||= {}
        entry = @contexts[kind]
        if !entry || entry[:version] != version
          entry&.fetch(:context)&.dispose
          context = MiniRacer::Context.new(timeout: 5000, max_memory: 64 * 1024 * 1024)
          @contexts[kind] = { context: context, version: version }
          context.eval(<<~JS)
            globalThis.setTimeout = () => { throw new Error("Async rendering is unsupported"); };
            globalThis.clearTimeout = () => {};
          JS
          context.eval(file.read)
        end
        @contexts.fetch(kind).fetch(:context).call("ComponentSSR.#{method}", *arguments)
      rescue StandardError
        @contexts&.delete(kind)&.fetch(:context)&.dispose
        raise
      end
    end
    private_class_method :call
  end
end
