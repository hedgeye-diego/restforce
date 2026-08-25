# frozen_string_literal: true

require_relative 'smoke_helper'

# The reason this directory exists.
#
# Restforce shipped a bug in 2018 where CGI.escape encoded a space in an id as
# '+', Salesforce did not decode it, and upsert silently created duplicates
# (705bf65). It reached production because the url looked correct in tests.
# Nothing verified at the webmock level can rule that class of bug out.
describe 'url encoding', :smoke do
  let(:client)   { SmokeHelper.client }
  let(:sobject)  { SmokeHelper.sobject }
  let(:ext_field) { SmokeHelper.external_id_text_field }

  before do
    unless ext_field
      typed = SmokeHelper.external_id_field
      skip(
        if typed
          "#{sobject}.#{typed} is an external id but is typed, so it cannot " \
            "hold a value with a space or a slash in it. This spec needs a " \
            "Text one - see spec/smoke/README.md"
        else
          "#{sobject} has no External ID field - see spec/smoke/README.md"
        end
      )
    end
  end

  # Space, slash and '@' each break a url in a different way.
  let(:hostile_value) { "smoke #{SmokeHelper.nonce}/a@b.com" }

  it 'round trips an external id holding characters that would break the url' do
    created = client.upsert!(sobject, ext_field,
                             ext_field => hostile_value,
                             **SmokeHelper.attributes)
    @created << [sobject, created]

    found = client.find(sobject, hostile_value, ext_field)

    expect(found.Id).to eq(created)
    expect(found[ext_field]).to eq(hostile_value)
  end

  it 'creates exactly one record, not one per encoding interpretation' do
    created = client.upsert!(sobject, ext_field,
                             ext_field => hostile_value,
                             **SmokeHelper.attributes)
    @created << [sobject, created]

    # The 2018 bug's signature: the space made Salesforce see a different key,
    # so a second upsert created a second record instead of updating the first.
    again = client.upsert!(sobject, ext_field,
                           ext_field => hostile_value,
                           **SmokeHelper.attributes(' again'))

    expect(again).to(satisfy { |result| result == true || result == created })

    count = client.query(
      "SELECT COUNT(Id) c FROM #{sobject} " \
      "WHERE #{SmokeHelper.label_field} LIKE 'Restforce smoke #{SmokeHelper.nonce}%'"
    ).first['c']

    expect(count).to be(1)
  end

  it 'reaches the same record through a composite subrequest' do
    created = client.upsert!(sobject, ext_field,
                             ext_field => hostile_value,
                             **SmokeHelper.attributes)
    @created << [sobject, created]

    results = client.composite! do |subrequest|
      subrequest.find_by(sobject, 'smoke1', hostile_value, ext_field)
    end

    expect(results.first['body']['Id']).to eq(created)
  end
end
