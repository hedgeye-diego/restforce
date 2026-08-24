# frozen_string_literal: true

require 'spec_helper'
require 'hashie/mash'

describe Restforce::Concerns::CompositeGraphAPI do
  let(:endpoint) { 'composite/graph' }
  let(:expected_output) do
    {
      graphs: [{ graphId: "g1",
                 compositeRequest: [{ method: "GET",
                                      url: "/services/data/v50.0/sobjects/Contact/xxx",
                                      referenceId: "c1" }] }]

    }
  end
  let(:response_hash) do
    {
      graphs: [
        {
          graphId: 'g1',
          graphResponse: {
            compositeResponse: []
          },
          isSuccessful: true
        }
      ]
    }
  end

  let(:max_graphs) do
    Restforce::Concerns::CompositeGraphAPI::CompositeGraph::MAX_GRAPH_COUNT
  end
  let(:max_nodes) do
    Restforce::Concerns::CompositeGraphAPI::CompositeGraph::MAX_NODE_COUNT
  end

  before do
    client.should_receive(:options).and_return(api_version: 50.0)
  end

  it "should populate has_error if any of the graphs have failed" do
    response_hash[:graphs].first['isSuccessful'] = false
    client.
      should_receive(:api_post).
      with(endpoint, expected_output.to_json).
      and_return(Hashie::Mash.new(body: response_hash))

    result = client.composite_graph do |builder|
      builder.graph('g1') do |subrequest|
        subrequest.find('Contact', 'c1', 'xxx')
      end
    end
    expect(result.hasErrors).to be_truthy
  end

  it "should NOT populate has_error if NONE of the graphs have failed" do
    client.
      should_receive(:api_post).
      with(endpoint, expected_output.to_json).
      and_return(Hashie::Mash.new(body: response_hash))

    result = client.composite_graph do |builder|
      builder.graph('g1') do |subrequest|
        subrequest.find('Contact', 'c1', 'xxx')
      end
    end
    expect(result.hasErrors).to be_falsey
  end

  context "when the built request exceeds Salesforce's limits" do
    it "should raise an ArgumentError when too many graphs are built" do
      client.should_not_receive(:api_post)

      expect do
        client.composite_graph do |builder|
          (max_graphs + 1).times { |i| builder.graph("g#{i}") }
        end
      end.to raise_error(ArgumentError)
    end

    it "should raise an ArgumentError when too many nodes are built" do
      client.should_not_receive(:api_post)

      expect do
        client.composite_graph do |builder|
          builder.graph('g1') do |subrequest|
            (max_nodes + 1).times { |i| subrequest.find('Contact', "c#{i}", 'xxx') }
          end
        end
      end.to raise_error(ArgumentError)
    end
  end

  context "when the response is not shaped as expected" do
    def post_and_return(body)
      client.
        should_receive(:api_post).
        and_return(Hashie::Mash.new(body: body))

      client.composite_graph do |builder|
        builder.graph('g1') { |subrequest| subrequest.find('Contact', 'c1', 'xxx') }
      end
    end

    it "should treat a graph with no isSuccessful as an error" do
      result = post_and_return(graphs: [{ graphId: 'g1' }])

      expect(result.hasErrors).to be(true)
    end

    it "should not explode when there are no graphs in the response" do
      result = post_and_return(irrelevant: true)

      expect(result.hasErrors).to be(false)
    end
  end

  describe "#composite_graph!" do
    let(:failed_response) do
      {
        graphs: [
          { graphId: 'g1',
            graphResponse: {
              compositeResponse: [
                { referenceId: 'c1', httpStatusCode: 400,
                  body: [{ errorCode: 'MALFORMED_ID', message: 'bad id' }] }
              ]
            },
            isSuccessful: false }
        ]
      }
    end

    def post_and_return(body)
      client.should_receive(:api_post).and_return(Hashie::Mash.new(body: body))

      client.composite_graph! do |builder|
        builder.graph('g1') { |subrequest| subrequest.find('Contact', 'c1', 'xxx') }
      end
    end

    it "should raise when a graph failed" do
      expect { post_and_return(failed_response) }.
        to raise_error(Restforce::CompositeAPIError, /MALFORMED_ID/)
    end

    it "should return the results when every graph succeeded" do
      expect(post_and_return(response_hash).hasErrors).to be(false)
    end
  end

  describe "#composite_graph_request" do
    it "should return the body that would be posted" do
      body = client.composite_graph_request do |builder|
        builder.graph('g1') do |subrequest|
          subrequest.find('Contact', 'c1', 'xxx')
        end
      end

      expect(body).to eq(expected_output)
    end

    it "should not send a request" do
      client.should_not_receive(:api_post)

      client.composite_graph_request do |builder|
        builder.graph('g1') { |subrequest| subrequest.find('Contact', 'c1', 'xxx') }
      end
    end

    it "should still raise when too many graphs are built" do
      expect do
        client.composite_graph_request do |builder|
          (max_graphs + 1).times { |i| builder.graph("g#{i}") }
        end
      end.to raise_error(ArgumentError)
    end
  end
end
