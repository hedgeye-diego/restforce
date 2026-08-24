# frozen_string_literal: true

require 'erb'

module Restforce
  module Resources
    class Requirements
      class << self
        def require_options(opts, *keys)
          keys.each do |key|
            raise ArgumentError, "You must include a #{key}" unless opts[key]
          end
        end
      end
    end

    class Base
      DEFAULT_API_VERSION = '26.0'

      attr_accessor :method, :opts

      def initialize(method, opts = {})
        @method = method
        @opts = opts
      end

      def to_request
        if reference_id.nil?
          raise ArgumentError, 'Must pass a reference id to be used as a subrequest.'
        end

        to_hash.merge({ referenceId: reference_id })
      end

      def to_hash
        {
          method: method.to_s.upcase,
          url: url
        }
      end

      class << self
        def encoded_path(path, params = {})
          [
            path,
            params.empty? ? nil : '?',
            # we don't want to encode reference_ids ie: '@{ref1.name}'
            unescape_reference_ids(URI.encode_www_form(params))
          ].join
        end

        # Even though SF documentation says query parameters must be URL encoded,
        # if you do so and include a reference_id syntax, You'll get a malformed
        # query because Salesforce doesn't fully URL decode everything
        # I suspect they look for reference_ids before decoding the url
        def unescape_reference_ids(str)
          str.gsub(/%40%7B([\w.%]+)%7D/) do
            "@{#{::Regexp.last_match(1).gsub('%5B', '[').gsub('%5D', ']')}}"
          end
        end

        # Percent-encodes a single path segment so that a value containing url
        # structural characters ('/', '?', '#', ...) cannot escape its segment.
        # Reference id syntax ('@{c1.Id}') is restored afterwards, since
        # Salesforce resolves those before decoding the url.
        def encode_segment(value)
          unescape_reference_ids(ERB::Util.url_encode(value.to_s))
        end

        # Internal: The opts a subrequest must carry before its url can be
        # built. Subclasses override this with the segments their .path needs.
        #
        # The base resource has no .path of its own, and takes its url from
        # the caller instead.
        #
        # Returns an Array of Symbol option names.
        def required_options
          []
        end

        # Internal: The opts handed to .path, in positional order. Defaults to
        # required_options, which is right whenever the required opts and the
        # path segments line up. Any option listed here but not required is
        # optional input that exists only to build the url, and is consumed in
        # the process.
        #
        # Returns an Array of Symbol option names.
        def url_options
          required_options
        end

        # Internal: Validates the opts a resource was given, applies the
        # default api version, and builds the url unless one was supplied.
        # Resources without a .path of their own get their url from the
        # caller and skip that last step.
        #
        # Raises ArgumentError if a required option is missing.
        #
        # Returns the Hash of options, with :url filled in.
        def build_option_url(opts = {})
          Requirements.require_options(opts, *required_options)
          options = { api_version: DEFAULT_API_VERSION }.merge(opts)
          options[:url] ||= build_url(options) if respond_to?(:path)
          options
        end

        private

        def build_url(options)
          arguments = url_options.map do |name|
            required_options.include?(name) ? options[name] : options.delete(name)
          end
          path(*arguments)
        end
      end

      protected

      def get_hash_for(key, as = key)
        respond_to?(key) && !send(key)&.empty? ? { as => send(key) } : {}
      end

      def respond_to_missing?(method, include_private = false)
        if opts&.key?(method)
          true
        else
          super
        end
      end

      def method_missing(method, *args, &)
        if opts&.key?(method)
          opts[method]
        else
          super
        end
      end
    end
  end
end
