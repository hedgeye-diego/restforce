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

        response = api_post('composite/graph', composite.to_json)
        results = response.body
        results[:has_errors] = results.graphs.any? do |graph|
          graph.isSuccessful == false
        end
        results
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

        def initialize(options = {})
          Restforce::Concerns::API.version_guard(50.0,
                                                 options[:api_version]) do
            @options = options
            @builder = GraphsBuilder.new(options)
          end
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

        def graph(name)
          graph_names << name
          subrequests = Restforce::Concerns::SubRequests::GraphSubrequests.new(options)
          yield(subrequests) if block_given?
          graphs << {
            graphId: name,
            compositeRequest: subrequests.requests
          }
        end
      end
    end
  end
end
