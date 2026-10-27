# frozen_string_literal: true

RSpec.describe DiscourseBlog::ArticlesController do
  fab!(:admin)
  fab!(:category)
  fab!(:drafts) { Fabricate(:private_category, group: Group[:staff]) }
  fab!(:topic) { Fabricate(:topic, category: drafts, user: admin) }
  fab!(:post) { Fabricate(:post, topic: topic, user: admin, raw: "Published body.") }

  before do
    enable_discourse_blog!(category: category, drafts: drafts)
    DiscourseBlog::GlimmerRenderer.stubs(:enabled?).returns(true)
  end

  it "sanitizes control-prefixed dynamic links and escapes ordinary template values" do
    links = (0..32).map { |codepoint| "#{codepoint.chr}JaVa\tscr\nipt:alert(1)" }
    links.each do |link|
      html =
        Nokogiri::HTML5.fragment(
          DiscourseBlog::GlimmerRenderer.render(
            "article",
            {
              "site" => {
                "url" => link,
              },
              "labels" => {
              },
              "article" => {
                "title" => "<script>alert(1)</script>",
                "body_html" => "<p>Cooked</p>",
              },
            },
            theme: {
            },
          ),
        )
      expect(html.at_css("a")["href"]).to start_with("unsafe:")
      expect(html.css("script")).to be_empty
      expect(html.at_css(".cooked p").text).to eq("Cooked")
    end
  end

  describe "#show" do
    it "renders the published snapshot with Glimmer while preserving the page shell and assets" do
      topic.update!(title: "Literal <em>title</em> & text")
      publication = DiscourseBlog::Publication.for_topic(topic)
      publication.publish!(admin)
      post.update!(raw: "Unpublished edit", cooked: "<p>Unpublished edit</p>")

      DiscourseBlog::GlimmerRenderer.stubs(:enabled?).returns(false)
      get "https://blog.example.com#{publication.path}"
      original = Nokogiri.HTML5(response.body)
      DiscourseBlog::GlimmerRenderer.stubs(:enabled?).returns(true)
      get "https://blog.example.com#{publication.path}?blog_ssr=1"

      expect(response.status).to eq(200)
      html = Nokogiri.HTML5(response.body)
      [original, html].each do |document|
        document.css("[nonce]").each { |node| node.remove_attribute("nonce") }
      end
      expect(response.body).to include("<!--%+b:0%-->")
      expect(html.at_css(".blog-article h1").text).to eq(topic.title)
      expect(html.css(".blog-article h1 em")).to be_empty
      expect(html.at_css(".cooked").text).to include("Published body.")
      expect(html.at_css(".cooked").text).not_to include(post.raw)
      %w[
        script[src]
        link[rel=stylesheet]
        meta[property]
        meta[name]
        script[type='application/ld+json']
      ].each do |selector|
        expect(html.css(selector).map(&:to_html)).to eq(original.css(selector).map(&:to_html))
      end
      expect(html.at_css("#discourse-comments")["data-topic-id"]).to eq(
        publication.discussion_topic_id.to_s,
      )
      expect(html.css("#data-preloaded")).to be_empty

      publication.unpublish!(admin)
      get "https://blog.example.com#{publication.path}?blog_ssr=1"
      expect(response.status).to eq(404)
    end

    it "keeps the normal renderer outside local environments" do
      publication = DiscourseBlog::Publication.for_topic(topic)
      publication.publish!(admin)
      DiscourseBlog::GlimmerRenderer.unstub(:enabled?)
      Rails.env.stubs(:local?).returns(false)

      get "https://blog.example.com#{publication.path}?blog_ssr=1"

      expect(response.status).to eq(200)
      expect(response.body).not_to include("<!--%+b:0%-->")
    end
  end
end
