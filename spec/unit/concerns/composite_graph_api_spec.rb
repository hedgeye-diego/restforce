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
    expect(result.has_errors).to be_truthy
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
    expect(result.has_errors).to be_falsey
  end

  context "when the built request exceeds Salesforce's limits" do
    let(:max_graphs) do
      Restforce::Concerns::CompositeGraphAPI::CompositeGraph::MAX_GRAPH_COUNT
    end
    let(:max_nodes) do
      Restforce::Concerns::CompositeGraphAPI::CompositeGraph::MAX_NODE_COUNT
    end

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

  context "in dry run mode" do
    it "should return a hash" do
      debug_output = client.composite_graph(dry_run: true) do |builder|
        builder.graph('g1') do |subrequest|
          subrequest.find('Contact', 'c1', 'xxx')
        end
      end

      expect(debug_output).to eq(expected_output)
    end
  end
end
