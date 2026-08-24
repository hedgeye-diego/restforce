# frozen_string_literal: true

module Restforce
  module Resources
    # Queries like Query, but also returns deleted and archived records.
    class QueryAll < Query
      class << self
        def resource
          'queryAll'
        end
      end
    end
  end
end
