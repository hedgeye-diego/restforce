# frozen_string_literal: true

require 'erb'

module Restforce
  module Resources
    # Internal: Guards against a resource being built without the opts its
    # url needs, or with values Salesforce will not accept.
    module Requirements
      # Salesforce documents the same rule for composite subrequests, composite
      # graph subrequests and sObject tree records: a reference id "must start
      # with a letter or a number" and "must not contain anything besides
      # letters, numbers, or underscores".
      #
      # Base.unescape_reference_ids depends on it too - its \w character class
      # is exactly this charset, so an id outside it silently fails to be
      # restored after encoding and reaches Salesforce as literal text.
      REFERENCE_ID = /\A[A-Za-z0-9][A-Za-z0-9_]*\z/

      module_function

      # Internal: Raises unless every named option is present and truthy.
      #
      # Returns nothing.
      def require_options(opts, *keys)
        keys.each do |key|
          raise ArgumentError, "You must include a #{key}" unless opts[key]
        end
      end

      # Internal: Raises unless the value is a reference id Salesforce accepts.
      #
      # Returns nothing.
      def require_reference_id(value)
        return if value.to_s.match?(REFERENCE_ID)

        raise ArgumentError,
              "The reference id #{value.inspect} is invalid. It must start " \
              "with a letter or a number, and hold nothing but letters, " \
              "numbers and underscores."
      end
    end

    class Base
      DEFAULT_API_VERSION = '26.0'

      attr_accessor :method, :opts

      def initialize(method, opts = {})
        @method = method
        @opts = opts
      end

      # Both are read straight out of opts rather than through method_missing,
      # which raises NameError for a missing key and would pre-empt the nil
      # check in to_request. build_option_url is what guarantees they are
      # there by the time a subrequest is built.
      def reference_id
        opts[:reference_id]
      end

      def url
        opts[:url]
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
        # default api version, and settles its url.
        #
        # A resource with a .path builds its own url from url_options unless
        # the caller supplied one. A resource without a .path can only be
        # given one - define_generic_subrequest sets it in the block it runs
        # ahead of this - so the url is required instead. Keeping that
        # requirement here rather than in required_options means a subclass
        # that adds a .path is never asked for a url it should be building.
        #
        # Raises ArgumentError if a required option is missing.
        #
        # Returns the Hash of options, with :url settled.
        def build_option_url(opts = {})
          Requirements.require_options(opts, *required_options)
          options = { api_version: DEFAULT_API_VERSION }.merge(opts)

          if respond_to?(:path)
            options[:url] ||= build_url(options)
          else
            Requirements.require_options(options, :url)
          end

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

      private

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
