# frozen_string_literal: true

module Restforce
  module Resources
    class Query < Base
      class << self
        def required_options
          %i[api_version soql]
        end

        def path(api_version, soql)
          encoded_path("/services/data/v#{api_version}/#{resource}", { q: soql })
        end

        # Internal: The endpoint this resource queries. QueryAll differs from
        # Query in this one word.
        def resource
          'query'
        end
      end
    end
  end
end
