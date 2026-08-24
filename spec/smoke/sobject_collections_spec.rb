# frozen_string_literal: true

require_relative 'smoke_helper'

describe 'sObject Collections API', :smoke do
  let(:client)  { SmokeHelper.client }
  let(:sobject) { SmokeHelper.sobject }

  before do
    skip('sObject Collections needs api_version 42.0 or later') if
      SmokeHelper.api_version.to_f < 42.0
  end

  def create_two
    results = client.collection_create! do |records|
      records.add(sobject, Name: "Restforce smoke #{SmokeHelper.nonce} a")
      records.add(sobject, Name: "Restforce smoke #{SmokeHelper.nonce} b")
    end
    results.each { |result| @created << [sobject, result['id']] }
    results.map { |result| result['id'] }
  end

  it 'creates several records in one call' do
    ids = create_two

    expect(ids.length).to be(2)
    expect(ids).to all(be_a(String))
  end

  it 'retrieves them by id, returning the fields asked for' do
    ids = create_two

    records = client.collection_get(sobject, ids, %w[Id Name])

    expect(records.map { |record| record['Id'] }).to eq(ids)
  end

  # Salesforce documents null in the position of any id it could not return.
  it 'returns nil in the place of an id that does not exist' do
    ids = create_two
    missing = "#{ids.first[0..-4]}zzz"

    records = client.collection_get(sobject, ids + [missing], %w[Id])

    expect(records.last).to be_nil
  end

  it 'updates records in one call' do
    ids = create_two

    client.collection_update! do |records|
      ids.each_with_index do |id, i|
        records.add(sobject, id: id, Name: "Restforce updated #{SmokeHelper.nonce} #{i}")
      end
    end

    expect(client.find(sobject, ids.first).Name).
      to eq("Restforce updated #{SmokeHelper.nonce} 0")
  end

  it 'deletes records in one call' do
    ids = create_two
    @created.clear

    results = client.collection_delete!(ids)

    expect(results.map { |result| result['success'] }).to all(be(true))
  end

  it 'raises rather than partially applying when all_or_none is set' do
    expect do
      client.collection_create! do |records|
        records.add(sobject, Name: "Restforce smoke #{SmokeHelper.nonce}")
        records.add(sobject, Bogus_Field__c: 'nope')
      end
    end.to raise_error(Restforce::ResponseError)

    count = client.query(
      "SELECT COUNT(Id) c FROM #{sobject} " \
      "WHERE Name LIKE 'Restforce smoke #{SmokeHelper.nonce}%'"
    ).first['c']

    expect(count).to be(0)
  end
end
