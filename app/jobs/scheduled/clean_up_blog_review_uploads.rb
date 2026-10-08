# frozen_string_literal: true

module ::Jobs
  class CleanUpBlogReviewUploads < ::Jobs::Scheduled
    every 1.hour

    def execute(args)
      DiscourseBlog::Review.release_inactive_uploads!
    end
  end
end
