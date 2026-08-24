# frozen_string_literal: true

require 'restforce/concerns/verbs'

module Restforce
  module Concerns
    module CompositeGraphAPI
      extend Restforce::Concerns::Verbs
      define_verbs :post

      # To see the request without sending it, use composite_graph_request
      #   result = client.composite_graph_request do |graphs|
      #     graphs.graph('g1') do |subrequest|
      #       subrequest.find('Contact', 'c1', 'xxx00000CuC7aAAF')
      #     end
      #   end => {:graphs=>
      #           [{:graphId=>"g1",
      #           :compositeRequest=>
      #            [{:method=>"GET",
      #              :url=>"/services/data/v57.0/sobjects/Contact/xxx00000CuC7aAAF",
      #              :referenceId=>"c1"}]}]}
      #
      # Regular usage without any options being passed
      #
      #   result = client.composite_graph do |graphs|
      #     graphs.graph('g1') do |subrequest|
      #       subrequest.find('Contact', 'c1', 'xxx00000CuC7aAAF')
      #     end
      #   end => #<Restforce::Mash graphs=
      #           [#<Restforce::Mash graphId="g1"
      #             graphResponse=#<Restforce::Mash …

      def composite_graph(&)
        composite = build_composite_graph(&)

        results = api_post('composite/graph', composite.to_json).body
        # Anything other than an explicit success counts as an error, so a
        # response missing isSuccessful surfaces rather than reading as a
        # silent success. Salesforce names this hasErrors on the sObject Tree
        # response but leaves it off the graph one, so we fill it in under the
        # same name rather than inventing a second spelling.
        results[:hasErrors] = failed_graphs(results).any?
        results
      end

      # Public: Runs a composite graph and raises if any graph failed, rather
      # than reporting it on the response.
      #
      # Each graph commits or rolls back on its own, so a failure here does
      # not mean nothing happened - the graphs that succeeded are on the
      # exception's response.
      #
      # Yields a GraphsBuilder to collect the graphs.
      #
      # Raises Restforce::CompositeAPIError if any graph failed.
      #
      # Returns the Restforce::Mash response.
      def composite_graph!(&)
        results = composite_graph(&)
        failed = failed_graphs(results)
        return results if failed.empty?

        raise CompositeAPIError.new(graph_error_code(failed.first), results)
      end

      # Public: Builds the request body composite_graph would post, without
      # sending anything. Validates exactly as composite_graph does, so a
      # request over the graph or node limit raises here too.
      #
      # Yields a GraphsBuilder to collect the graphs.
      #
      # Examples
      #
      #   client.composite_graph_request do |graphs|
      #     graphs.graph('g1') do |subrequest|
      #       subrequest.find('Contact', 'c1', 'xxx00000CuC7aAAF')
      #     end
      #   end
      #   # => { graphs: [{ graphId: 'g1',
      #   #                 compositeRequest: [{ method: 'GET',
      #   #                                      url: '/services/data/…',
      #   #                                      referenceId: 'c1' }] }] }
      #
      # Returns the Hash body that would be posted.
      def composite_graph_request(&)
        build_composite_graph(&).to_hash
      end

      private

      # Internal: The graphs Salesforce did not report an explicit success for.
      #
      # Returns an Array of graphs.
      def failed_graphs(results)
        (results[:graphs] || []).reject { |graph| graph[:isSuccessful] }
      end

      # Internal: Digs the first real error code out of a failed graph, since
      # the graph itself carries only an id and its subrequests' responses.
      #
      # Returns the String error code, or the graph id if none is present.
      def graph_error_code(graph)
        subresponses = graph.dig(:graphResponse, :compositeResponse) || []
        errored = subresponses.find { |sub| sub[:body].is_a?(Array) && sub[:body].any? }

        errored&.dig(:body, 0, :errorCode) || graph[:graphId]
      end

      # Internal: Collects the caller's graphs and validates them. Shared by
      # composite_graph and composite_graph_request so both validate
      # identically.
      #
      # Returns the CompositeGraph.
      def build_composite_graph(&)
        composite = CompositeGraph.new(options)
        composite.yield_builder(&)
        composite.validate!
        composite
      end

      class CompositeGraph
        attr_accessor :options, :builder

        MAX_GRAPH_COUNT = 75
        MAX_NODE_COUNT  = 500

        # The Composite Graph resource was introduced in the Salesforce API
        # v50.0.
        MIN_API_VERSION = 50.0

        def initialize(options = {})
          Restforce::Concerns::API.version_guard(MIN_API_VERSION,
                                                 options[:api_version])
          @options = options
          @builder = GraphsBuilder.new(options)
        end

        def validate!
          if builder.graphs_count > MAX_GRAPH_COUNT
            raise ArgumentError, "Cannot have more than #{MAX_GRAPH_COUNT} graphs."
          end

          return unless builder.node_count > MAX_NODE_COUNT

          raise ArgumentError, "Cannot have more than #{MAX_NODE_COUNT} nodes."
        end

        def yield_builder
          yield(builder) if block_given?
        end

        def to_hash
          {
            graphs: builder.graphs
          }
        end

        def to_json(*_args)
          to_hash.to_json
        end
      end

      class GraphsBuilder
        attr_accessor :options, :graphs, :graph_names

        def initialize(options = {})
          @options = options
          @graphs = []
          @graph_names = Restforce::Concerns::
                           SubRequests::UniqueNameSet.new("GraphName")
        end

        def graphs_count
          graphs.size
        end

        def node_count
          graphs.sum { |graph| graph[:compositeRequest].size }
        end

        # Public: Adds one graph of related subrequests.
        #
        # The name is registered only once the graph has been built, so a
        # build that raises part way through leaves the name free to use
        # again rather than burning it for the rest of the request.
        #
        # Returns the Array of graphs built so far.
        def graph(name)
          subrequests = Restforce::Concerns::SubRequests::GraphSubrequests.new(options)
          yield(subrequests) if block_given?

          graph_names << name
          graphs << {
            graphId: name,
            compositeRequest: subrequests.requests
          }
        end
      end
    end
  end
end
