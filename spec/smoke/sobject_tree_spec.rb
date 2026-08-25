# frozen_string_literal: true

require_relative 'smoke_helper'

describe 'sObject Tree API', :smoke do
  let(:client) { SmokeHelper.client }

  # The tree resource needs a real parent-child relationship, so unlike the
  # other smoke specs this one is fixed to Account and Contact rather than
  # following SF_SOBJECT.
  let(:root)  { 'Account' }
  let(:child) { 'Contacts' }

  it 'creates a parent and its children in one call' do
    result = client.composite_tree(root) do |accounts|
      accounts.add(:acc1, **SmokeHelper.attributes('', root))
      accounts.embed(child, 'Contact') do |contacts|
        # FirstName is set because orgs commonly carry a validation rule
        # requiring it, and a smoke spec should exercise the API rather than
        # trip over local configuration.
        contacts.add(:con1, FirstName: 'Smoke', LastName: "Smith #{SmokeHelper.nonce}")
        contacts.add(:con2, FirstName: 'Smoke', LastName: "Jones #{SmokeHelper.nonce}")
      end
    end

    # Only the account is tracked: deleting it cascades to its contacts, and
    # the sweep catches anything that does not.
    account = result.results.find { |record| record.referenceId.to_s.start_with?('acc') }
    @created << [root, account.id]

    expect(result.hasErrors).to be(false)
    expect(result.results.length).to be(3)
  end

  it 'maps every reference id in the response' do
    result = client.composite_tree(root) do |accounts|
      accounts.add(:acc1, **SmokeHelper.attributes('', root))
    end

    @created << [root, result.results.first.id]

    expect(result.results.map(&:referenceId)).to eq(['acc1'])
  end

  # The resource is all or nothing, and Salesforce signals a rejected tree with
  # HTTP 400 rather than a 200 carrying hasErrors. Restforce's raise_error
  # middleware turns that into a ResponseError before composite_tree returns,
  # so the plain method raises too and composite_tree! never gets to.
  it 'creates nothing at all when one record is rejected' do
    expect do
      client.composite_tree(root) do |accounts|
        accounts.add(:acc1, **SmokeHelper.attributes('', root))
        accounts.add(:acc2, Bogus_Field__c: 'nope')
      end
    end.to raise_error(Restforce::ResponseError)

    label = SmokeHelper.label_field(root)
    count = client.query(
      "SELECT COUNT(Id) c FROM #{root} " \
      "WHERE #{label} LIKE 'Restforce smoke #{SmokeHelper.nonce}%'"
    ).first['c']

    expect(count).to be(0)
  end
end
