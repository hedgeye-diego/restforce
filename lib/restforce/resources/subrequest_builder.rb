# frozen_string_literal: true

module Restforce
  module Resources
    module SubrequestBuilder
      def define_subrequest(subrequest_method, clazz, http_method, *params)
        define_method subrequest_method do |*args|
          # Resolved into a local rather than reassigned: clazz is captured
          # from the enclosing define_subrequest, so writing to it would
          # rewrite it for every later call to this method.
          resource = clazz.is_a?(Class) ? clazz : Object.const_get(clazz)

          opts = {}
          params.each_with_index do |el, idx|
            opts[el] = args[idx]
          end
          if args.length > params.length && args[-1].is_a?(Hash)
            opts.merge!({ api_version: options[:api_version] }.merge(args[-1]))
          else
            opts[:api_version] = options[:api_version]
          end

          Restforce::Resources::Requirements.require_options(opts, :reference_id)
          Restforce::Resources::Requirements.require_options(opts, :api_version)
          Restforce::Resources::Requirements.require_reference_id(opts[:reference_id])

          object = resource.new(http_method, opts)
          yield(object) if block_given?
          object.opts = resource.build_option_url(object.opts)

          record_subrequest(opts[:reference_id], object.to_request)
        end
      end

      # subrequest.get_layout_description(sobject_name, reference_id)
      # subrequest.describe_layout_description(sobject_name, reference_id)
      #
      # sobject       - The String name of the sobject.
      # reference_id  - The reference id to match with the response

      def define_generic_subrequest(subrequest_method, clazz,
                                    http_methods, *params, &block)
        http_methods.each do |http_method|
          http_method_name = rename_http_method_to_friendly_name(http_method,
                                                                 params)
          subrequest_method_name = [http_method_name, subrequest_method].join('_')
          define_subrequest(subrequest_method_name,
                            clazz,
                            http_method,
                            *params,
                            &block)
        end
      end

      def rename_http_method_to_friendly_name(http_method, params = [])
        case http_method
        when :head
          :describe
        when :post
          :create
        when :patch
          if params.intersect?(%i[field_name field_value])
            :upsert
          else
            :update
          end
        else
          http_method
        end
      end
    end
  end
end
