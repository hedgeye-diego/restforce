# frozen_string_literal: true

module Restforce
  module Resources
    class SObjectBasic < Base
      def to_hash
        {
          method: method.to_s.upcase,
          url: url
        }.merge(get_hash_for(:body))
      end

      class << self
        def required_options
          %i[sobject_name api_version]
        end

        def url_options
          %i[api_version sobject_name]
        end

        def path(api_version, sobject_name)
          "/services/data/v#{api_version}/sobjects/#{sobject_name}"
        end
      end
    end
  end
end
