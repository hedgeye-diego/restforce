# frozen_string_literal: true

require_relative 'smoke_helper'

describe 'Composite API', :smoke do
  let(:client)  { SmokeHelper.client }
  let(:sobject) { SmokeHelper.sobject }

  it 'creates a record and reads it back in one call' do
    results = client.composite! do |subrequest|
      subrequest.create(sobject, 'made', Name: "Restforce smoke #{SmokeHelper.nonce}")
      subrequest.find(sobject, 'read', '@{made.id}')
    end

    created = results.first['body']['id']
    @created << [sobject, created]

    expect(results.last['body']['Id']).to eq(created)
  end

  it 'resolves a reference id between subrequests' do
    results = client.composite! do |subrequest|
      subrequest.create(sobject, 'made', Name: "Restforce smoke #{SmokeHelper.nonce}")
      subrequest.update(sobject, 'renamed',
                        Id: '@{made.id}', Name: "Restforce renamed #{SmokeHelper.nonce}")
    end

    created = results.first['body']['id']
    @created << [sobject, created]

    expect(client.find(sobject, created).Name).
      to eq("Restforce renamed #{SmokeHelper.nonce}")
  end

  it 'runs a query subrequest' do
    results = client.composite! do |subrequest|
      subrequest.query("SELECT Id FROM #{sobject} LIMIT 1", 'q1')
    end

    expect(results.first['body']).to have_key('records')
  end

  # Salesforce lists POST, PUT, PATCH, GET and DELETE as the accepted subrequest
  # methods, and omits HEAD - but HEAD is a documented method on the underlying
  # resource. This spec is what settles whether headers_by is usable.
  it 'either accepts or rejects a HEAD subrequest, on the record' do
    ext_field = SmokeHelper.external_id_field
    skip("#{sobject} has no External ID field") unless ext_field

    begin
      results = client.composite do |subrequest|
        subrequest.headers_by(sobject, 'peek', "nothing-#{SmokeHelper.nonce}", ext_field)
      end
      warn "[smoke] HEAD subrequest accepted, status " \
           "#{results.first['httpStatusCode']}"
    rescue Restforce::ResponseError => e
      warn "[smoke] HEAD subrequest rejected: #{e.message}"
      raise
    end
  end
end
