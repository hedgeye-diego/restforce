# frozen_string_literal: true

require_relative 'smoke_helper'

describe 'Composite Graph API', :smoke do
  let(:client)  { SmokeHelper.client }
  let(:sobject) { SmokeHelper.sobject }

  before do
    skip('composite graph needs api_version 50.0 or later') if
      SmokeHelper.api_version.to_f < 50.0
  end

  # On a failed subrequest the body is an array of errors rather than the
  # created record, so dig it out only once the graph is known to have worked.
  def created_id(graph)
    unless graph.isSuccessful
      raise "graph #{graph.graphId} failed: #{graph.graphResponse.to_json}"
    end

    graph.graphResponse.compositeResponse.first.body.id
  end

  it 'commits a graph and reports it successful' do
    result = client.composite_graph do |graphs|
      graphs.graph('g1') do |subrequest|
        subrequest.create(sobject, 'made', **SmokeHelper.attributes)
      end
    end

    created = created_id(result.graphs.first)
    @created << [sobject, created]

    expect(result.hasErrors).to be(false)
  end

  # The reason to reach for graphs over composite: one graph failing must not
  # take down the other. If this ever fails, the resource is not behaving the
  # way the whole feature assumes.
  it 'rolls back only the graph that failed' do
    result = client.composite_graph do |graphs|
      graphs.graph('good') do |subrequest|
        subrequest.create(sobject, 'ok', **SmokeHelper.attributes)
      end

      graphs.graph('bad') do |subrequest|
        subrequest.create(sobject, 'boom', Bogus_Field__c: 'nope')
      end
    end

    good, bad = result.graphs.partition { |graph| graph.graphId == 'good' }.map(&:first)

    created = created_id(good)
    @created << [sobject, created] if created

    expect(bad.isSuccessful).to be(false)
    expect(result.hasErrors).to be(true)
  end

  it 'raises from composite_graph! when a graph fails' do
    expect do
      client.composite_graph! do |graphs|
        graphs.graph('bad') do |subrequest|
          subrequest.create(sobject, 'boom', Bogus_Field__c: 'nope')
        end
      end
    end.to raise_error(Restforce::CompositeAPIError)
  end

  it 'resolves a reference id inside a graph' do
    result = client.composite_graph do |graphs|
      graphs.graph('g1') do |subrequest|
        subrequest.create(sobject, 'made', **SmokeHelper.attributes)
        subrequest.find(sobject, 'read', '@{made.id}')
      end
    end

    created = created_id(result.graphs.first)
    @created << [sobject, created]

    responses = result.graphs.first.graphResponse.compositeResponse
    expect(responses.last.body.Id).to eq(created)
  end
end
