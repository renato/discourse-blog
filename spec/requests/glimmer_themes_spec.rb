# frozen_string_literal: true

RSpec.describe DiscourseBlog::ThemesController do
  fab!(:admin)
  fab!(:category)
  fab!(:drafts) { Fabricate(:private_category, group: Group[:staff]) }
  fab!(:topic) { Fabricate(:topic, category: drafts, user: admin) }
  fab!(:first_post) { Fabricate(:post, topic: topic, user: admin, raw: "Published article body.") }

  before do
    enable_discourse_blog!(category: category, drafts: drafts)
    DiscourseBlog::GlimmerRenderer.stubs(:enabled?).returns(true)
    https!
    get "https://test.localhost/session/#{admin.encoded_username}/become"
  end

  let(:attributes) do
    DiscourseBlog::BlogTheme.defaults.merge(
      "name" => "Glimmer draft",
      "template_layout" =>
        '<header data-glimmer-header>{{@site.title}}</header><main id="main">{{@content_html}}</main><footer data-glimmer-footer>Footer</footer>',
      "template_index" =>
        "<h1 data-glimmer-index>{{@site.title}}</h1>{{#each @articles as |article|}}<a href={{article.url}}>{{article.title}}</a>{{/each}}",
    )
  end

  describe "#create" do
    it "compiles on save and renders published revisions with no compiler available on requests" do
      publication = DiscourseBlog::Publication.for_topic(topic)
      publication.publish!(admin)
      post "/blog/themes.json", params: { theme: attributes }
      expect(response.status).to eq(201)
      draft = response.parsed_body
      expect(draft.fetch("glimmer").fetch("templates").keys).to contain_exactly(
        *DiscourseBlog::TemplateRenderer::PAGES,
      )

      get draft.fetch("preview_url")
      expect(response.status).to eq(200)
      expect(response.body).to include(
        "data-glimmer-header",
        "data-glimmer-index",
        "data-glimmer-footer",
      )
      post "https://test.localhost/blog/themes/#{draft.fetch("id")}/activate.json",
           params: {
             revision: 1,
           }
      expect(response.status).to eq(200)

      Dir.mktmpdir do |directory|
        build = DiscourseBlog::GlimmerRenderer::BUILD
        %w[render.js builtin.json].each { |file| FileUtils.cp(build.join(file), directory) }
        stub_const(DiscourseBlog::GlimmerRenderer, :BUILD, Pathname.new(directory)) do
          ["/", "/archive", "/about", publication.path, "/missing-page"].each do |path|
            get "https://blog.example.com#{path}"
            expect(response.status).to eq(path == "/missing-page" ? 404 : 200)
            expect(response.body).to include("data-glimmer-header", "data-glimmer-footer")
            expect(response.body).not_to include('id="data-preloaded"')
          end
          get "https://blog.example.com#{publication.path}"
          expect(Nokogiri.HTML5(response.body).at_css(".cooked").text).to include(
            "Published article body.",
          )
        end
      end

      put "https://test.localhost/blog/themes/#{draft.fetch("id")}.json",
          params: {
            revision: 1,
            theme: attributes.merge("template_index" => "Draft-only change"),
          }
      expect(response.status).to eq(200)
      get "https://blog.example.com/"
      expect(response.body).to include("data-glimmer-index")
      get "https://blog.example.com/?blog_safe_mode=1"
      expect(response.body).to include('class="blog__header"')
      expect(response.body).not_to include("data-glimmer-header")
    end

    it "rejects invalid syntax, unknown components, and unescaped expressions without saving" do
      ["{{#if @site.title}}", "<UnknownComponent />", "{{{@site.title}}}"].each do |source|
        post "/blog/themes.json", params: { theme: attributes.merge("template_index" => source) }
        expect(response.status).to eq(400)
        expect(DiscourseBlog::BlogTheme.all).to be_empty
      end
    end

    it "keeps Liquid themes in a separate store" do
      DiscourseBlog::GlimmerRenderer.stubs(:enabled?).returns(false)
      original =
        DiscourseBlog::BlogTheme.save(
          DiscourseBlog::BlogTheme.defaults.merge("name" => "Liquid"),
          user: admin,
        )
      DiscourseBlog::GlimmerRenderer.stubs(:enabled?).returns(true)
      expect(DiscourseBlog::BlogTheme.all).to be_empty
      post "/blog/themes.json", params: { theme: attributes }
      expect(response.status).to eq(201)
      DiscourseBlog::GlimmerRenderer.stubs(:enabled?).returns(false)
      expect(DiscourseBlog::BlogTheme.all.map { |theme| theme["id"] }).to eq([original["id"]])
    end
  end

  describe "#update" do
    it "keeps the saved revision after a compilation error" do
      theme = DiscourseBlog::BlogTheme.save(attributes, user: admin)
      put "/blog/themes/#{theme["id"]}.json",
          params: {
            revision: 1,
            theme: attributes.merge("template_layout" => "{{#if}}"),
          }
      expect(response.status).to eq(400)
      expect(DiscourseBlog::BlogTheme.find(theme["id"])).to eq(theme)
    end
  end

  describe "#import" do
    it "round-trips Glimmer source and rejects it in Liquid mode" do
      theme = DiscourseBlog::BlogTheme.save(attributes, user: admin)
      get "/blog/themes/#{theme["id"]}/export"
      expect(response.status).to eq(200)
      Tempfile.create(%w[glimmer-theme .zip]) do |file|
        file.binmode
        file.write(response.body)
        file.flush
        post "/blog/themes/import.json",
             params: {
               file: Rack::Test::UploadedFile.new(file.path, "application/zip"),
             }
        expect(response.status).to eq(201)
        expect(response.parsed_body["template_layout"]).to eq(attributes["template_layout"])
        expect(response.parsed_body.dig("glimmer", "version")).to eq(
          theme.dig("glimmer", "version"),
        )
        DiscourseBlog::GlimmerRenderer.stubs(:enabled?).returns(false)
        post "/blog/themes/import.json",
             params: {
               file: Rack::Test::UploadedFile.new(file.path, "application/zip"),
             }
        expect(response.status).to eq(400)
      end
    end
  end

  describe "#authoring" do
    it "provides Glimmer source and resolved example data to the existing editor" do
      get "/blog/theme-authoring.json"
      expect(response.status).to eq(200)
      expect(response.parsed_body["template_engine"]).to eq("glimmer")
      expect(response.parsed_body.dig("templates", "template_layout")).to include("@content_html")
      expect(response.parsed_body.dig("variables", "site", "about_html")).not_to include("Proc")
    end
  end

  describe "#working_preview" do
    it "compiles unsaved templates for preview without activating them" do
      post "/blog/theme-authoring/preview.json", params: { theme: attributes, page: "index" }
      expect(response.status).to eq(201)
      get response.parsed_body.fetch("url")
      expect(response.status).to eq(200)
      expect(response.body).to include("data-glimmer-index", "data-glimmer-header")
      expect(DiscourseBlog::BlogTheme.all).to be_empty
    end
  end
end
