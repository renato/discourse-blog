# frozen_string_literal: true

RSpec.describe DiscourseBlog::Revision do
  fab!(:topic)
  fab!(:post) { Fabricate(:post, topic: topic) }

  describe ".capture" do
    it "freezes reading time and the generated excerpt with the article" do
      post.update!(cooked: "<p>#{"word " * 441}</p>")
      publication = DiscourseBlog::Publication.new(topic: topic, path: "/article", excerpt: "")

      data = described_class.capture(publication, topic)
      revision = described_class.new(data: data)

      expect(data["reading_minutes"]).to eq(3)
      expect(data["display_excerpt"]).to eq(
        PrettyText.excerpt(post.cooked, 240, strip_links: true, strip_tags: true),
      )
      expect(revision.reading_minutes).to eq(3)
      expect(revision.display_excerpt).to eq(data["display_excerpt"])
    end

    it "preserves explicit excerpts and a minimum reading time" do
      post.update!(cooked: "")
      publication =
        DiscourseBlog::Publication.new(topic: topic, path: "/article", excerpt: "Summary")

      data = described_class.capture(publication, topic)

      expect(data.slice("reading_minutes", "display_excerpt")).to eq(
        "reading_minutes" => 1,
        "display_excerpt" => "Summary",
      )
    end
  end

  describe "legacy revision summaries" do
    it "derives summaries without modifying stored revisions" do
      publication = DiscourseBlog::Publication.create!(topic: topic, path: "/article")
      data = { "cooked" => "<p>#{"word " * 221}</p>", "raw" => "Article", "excerpt" => "" }
      revision =
        described_class.create!(
          publication: publication,
          source_topic: topic,
          creator: topic.user,
          data: data,
        )

      2.times do
        loaded = described_class.find(revision.id)
        expect(loaded.reading_minutes).to eq(2)
        expect(loaded.display_excerpt).to eq(
          PrettyText.excerpt(data["cooked"], 240, strip_links: true, strip_tags: true),
        )
      end
      expect(revision.reload.data).to eq(data)
    end
  end
end
