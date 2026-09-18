# frozen_string_literal: true

module ::DiscourseBlog
  class Revision < ActiveRecord::Base
    self.table_name = "discourse_blog_revisions"
    belongs_to :publication
    belongs_to :source_topic, class_name: "Topic"
    belongs_to :creator, class_name: "User"
    belongs_to :approver, class_name: "User", optional: true
    has_many :upload_references, as: :target, dependent: :destroy
    after_create :retain_uploads
    attr_readonly :data, :publication_id, :source_topic_id, :creator_id

    def self.capture(publication, source)
      post = source.first_post
      metadata = publication.editorial_metadata
      upload = source.image_upload
      metadata.merge(summary(post.cooked.to_s, metadata["excerpt"])).merge(
        "title" => source.title,
        "raw" => post.raw,
        "cooked" => post.cooked,
        "author_name" => source.user&.name.presence || source.user&.username,
        "image_url" => upload && !upload.secure? ? upload.url : "",
        "tags" => source.tags.visible(Guardian.new).pluck(:name),
      )
    end

    def self.summary(cooked, excerpt)
      {
        "reading_minutes" => [
          (PrettyText.excerpt(cooked, 100_000, strip_tags: true).split.size / 220.0).ceil,
          1,
        ].max,
        "display_excerpt" =>
          excerpt.presence || PrettyText.excerpt(cooked, 240, strip_links: true, strip_tags: true),
      }
    end

    def title
      data["title"]
    end

    def cooked
      data["cooked"]
    end

    def reading_minutes
      summary["reading_minutes"]
    end

    def display_excerpt
      summary["display_excerpt"]
    end

    def raw
      data["raw"]
    end

    private

    def summary
      @summary ||=
        if data.key?("reading_minutes") && data.key?("display_excerpt")
          data.slice("reading_minutes", "display_excerpt")
        elsif persisted?
          Discourse
            .cache
            .fetch("discourse-blog:revision-summary:v1:#{cache_key_with_version}") do
              self.class.summary(cooked.to_s, data["excerpt"])
            end
        else
          self.class.summary(cooked.to_s, data["excerpt"])
        end
    end

    def retain_uploads
      UploadReference.ensure_exist!(upload_ids: Upload.extract_upload_ids(raw), target: self)
    end
  end
end

# == Schema Information
#
# Table name: discourse_blog_revisions
#
#  id              :bigint           not null, primary key
#  approved_at     :datetime
#  data            :jsonb            not null
#  created_at      :datetime         not null
#  updated_at      :datetime         not null
#  approver_id     :bigint
#  creator_id      :bigint           not null
#  publication_id  :bigint           not null
#  source_topic_id :bigint           not null
#
# Indexes
#
#  index_discourse_blog_revisions_on_publication_id_and_id  (publication_id,id)
#
