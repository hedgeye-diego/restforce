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
      accounts.add(:acc1, Name: "Restforce smoke #{SmokeHelper.nonce}")
      accounts.embed(child, 'Contact') do |contacts|
        contacts.add(:con1, LastName: "Smith #{SmokeHelper.nonce}")
        contacts.add(:con2, LastName: "Jones #{SmokeHelper.nonce}")
      end
    end

    result.results.each do |record|
      type = record.referenceId.to_s.start_with?('acc') ? 'Account' : 'Contact'
      @created << [type, record.id]
    end

    expect(result.hasErrors).to be(false)
    expect(result.results.length).to be(3)
  end

  it 'maps every reference id in the response' do
    result = client.composite_tree(root) do |accounts|
      accounts.add(:acc1, Name: "Restforce smoke #{SmokeHelper.nonce}")
    end

    @created << [root, result.results.first.id]

    expect(result.results.map(&:referenceId)).to eq(['acc1'])
  end

  # The resource is all or nothing, which is what makes composite_tree! raise
  # by default rather than reporting on the response.
  it 'creates nothing at all when one record is rejected' do
    expect do
      client.composite_tree!(root) do |accounts|
        accounts.add(:acc1, Name: "Restforce smoke #{SmokeHelper.nonce}")
        accounts.add(:acc2, Bogus_Field__c: 'nope')
      end
    end.to raise_error(Restforce::CompositeAPIError)

    count = client.query(
      "SELECT COUNT(Id) c FROM #{root} " \
      "WHERE Name LIKE 'Restforce smoke #{SmokeHelper.nonce}%'"
    ).first['c']

    expect(count).to be(0)
  end
end
