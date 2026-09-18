# frozen_string_literal: true

RSpec.describe DiscourseBlog::TemplateRenderer do
  describe ".render" do
    it "escapes dynamic text while allowing only server-produced HTML fragments" do
      output =
        described_class.render(
          "article",
          {
            "title" => '<img src=x onerror="alert(1)">',
            "body" => described_class::Html.new("<p>Safe cooked content</p>"),
          },
          theme: {
            "template_article" => "<h1>{{ title }}</h1><div>{{ body }}</div>",
          },
        )
      document = Nokogiri::HTML5.fragment(output)
      expect(document.at_css("h1").text).to eq('<img src=x onerror="alert(1)">')
      expect(document.css("img")).to be_empty
      expect(document.at_css("div p").text).to eq("Safe cooked content")
    end

    it "does not expose request, session, model methods, or global Liquid registrations" do
      output =
        described_class.render(
          "article",
          { "article" => { "title" => "Public title" } },
          theme: {
            "template_article" =>
              "{{ article.title }}|{{ article.class }}|{{ request }}|{{ session }}|{{ site_settings }}",
          },
        )
      expect(output).to eq("Public title||||")
      expect(described_class::ENVIRONMENT).not_to equal(Liquid::Environment.default)
    end

    it "falls back to the built-in page after resource exhaustion or an unknown filter" do
      assigns = { "site" => {}, "labels" => { "about" => "About fallback" } }
      [
        "{% for item in (1..1000000000) %}x{% endfor %}",
        "{% for a in (1..1000) %}{% for b in (1..1000) %}x{% endfor %}{% endfor %}",
        '{{ "hello" | unsupported_filter }}',
      ].each do |source|
        output = described_class.render("about", assigns, theme: { "template_about" => source })
        expect(output).to include("About fallback")
      end
    end

    it "isolates assignments, counters, and strict-variable errors between renders" do
      theme = {
        "template_article" =>
          "{% if title %}{% assign previous = title %}{% endif %}{{ previous }}:{% increment counter %}:{{ title }}",
      }
      expect(described_class.render("article", { "title" => "First" }, theme: theme)).to eq(
        "First:0:First",
      )
      expect(described_class.render("article", {}, theme: theme)).to eq(":0:")
      expect(described_class.render("article", {}, theme: theme, diagnostics: true)).to include(
        "data-template-diagnostic",
      )
      expect(described_class.render("article", { "title" => "Second" }, theme: theme)).to eq(
        "Second:0:Second",
      )
    end

    it "isolates concurrent renders of the same cached template" do
      theme = {
        "template_article" =>
          "{% assign saved = title %}{% increment counter %}:{{ saved }}:{{ title }}",
      }
      ready = Queue.new
      start = Queue.new
      threads =
        4.times.map do |index|
          Thread.new do
            ready << true
            start.pop
            5.times.map do
              described_class.render("article", { "title" => "Reader #{index}" }, theme: theme)
            end
          end
        end
      4.times { ready.pop }
      4.times { start << true }

      threads.each_with_index do |thread, index|
        expect(thread.value).to eq(["0:Reader #{index}:Reader #{index}"] * 5)
      end
    end

    it "resets resource limits after a cached template fails" do
      theme = { "template_about" => "{% for item in (1..count) %}x{% endfor %}" }
      assigns = { "count" => 100_000, "site" => {}, "labels" => { "about" => "Fallback" } }
      expect(described_class.render("about", assigns, theme: theme)).to include("Fallback")
      expect(described_class.render("about", { "count" => 2 }, theme: theme)).to eq("xx")
    end

    it "keeps the cached template untouched by a failing render" do
      source = "{% for item in (1..count) %}x{% endfor %}"
      theme = { "template_article" => source }
      expect(
        described_class.render("article", { "count" => 100_000 }, theme: theme, diagnostics: true),
      ).to include("data-template-diagnostic")
      expect(described_class::TEMPLATES[source].errors).to be_empty
    end

    it "renders changed template sources immediately" do
      theme = { "template_article" => "Before {{ title }}" }
      expect(described_class.render("article", { "title" => "edit" }, theme: theme)).to eq(
        "Before edit",
      )
      theme["template_article"] = "After {{ title }}"
      expect(described_class.render("article", { "title" => "edit" }, theme: theme)).to eq(
        "After edit",
      )
    end

    it "ignores custom templates when custom rendering is disabled" do
      output =
        described_class.render(
          "not_found",
          { "labels" => { "not_found_title" => "Not found" }, "site" => {} },
          theme: {
            "template_not_found" => "custom markup",
          },
          custom: false,
        )
      expect(output).to include("Not found")
      expect(output).not_to include("custom markup")
    end
  end

  describe ".validate!" do
    it "rejects includes, render tags, invalid syntax, excessive nesting, and oversized sources" do
      [
        '{% include "/etc/passwd" %}',
        '{% render "secret" %}',
        "{% if %}",
        "{% if true %}" * 110 + "{% endif %}" * 110,
        "x" * 65_537,
      ].each do |source|
        expect { described_class.validate!(source) }.to raise_error(Discourse::InvalidParameters)
      end
    end
  end
end
