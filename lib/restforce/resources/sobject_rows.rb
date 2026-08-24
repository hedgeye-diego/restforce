# frozen_string_literal: true

module Restforce
  module Resources
    class SObjectRows < Base
      def to_hash
        {
          method: method.to_s.upcase,
          url: url
        }.merge(
          get_hash_for(:body)
        ).merge(
          get_hash_for(:http_headers, :httpHeaders)
        )
      end

      class << self
        def required_options
          %i[sobject_name api_version id]
        end

        # :fields is optional, and exists only to build the query string, so
        # build_option_url consumes it.
        def url_options
          %i[api_version sobject_name id fields]
        end

        def path(api_version, sobject_name, sobject_id, fields = [])
          fields_value = ERB::Util.url_encode(Array(fields).join(','))
          fields_query = fields_value.empty? ? '' : "?fields=#{fields_value}"
          "/services/data/v#{api_version}/sobjects/" \
            "#{sobject_name}/#{encode_segment(sobject_id)}#{fields_query}"
        end
      end
    end
  end
end
