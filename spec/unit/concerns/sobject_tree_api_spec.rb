# frozen_string_literal: true

require 'spec_helper'
require 'hashie/mash'

describe Restforce::Concerns::SObjectTreeAPI do
  let(:endpoint) { "composite/tree/Account" }
  let(:expected_tree) do
    { records: [{ :attributes => { type: "Account",
                                   referenceId: :acc1 },
                  :Name => "Widget Factory",
                  "Contacts" =>
                    { records: [{ :attributes =>
                                    { type: "Contact",
                                      referenceId: :contact1 },
                                  :FirstName => "John",
                                  :LastName => "Smith",
                                  :Email => "test@restforce.com",
                                  "Objects" =>
                                    { records: [{
                                      attributes:
                                        { type: "Object",
                                          referenceId: :obj1 },
                                      accountId: "@{acc1.Id}"
                                    }] } }] } },
                { attributes: { type: "Account",
                                referenceId: :acc2 },
                  Name: "Width Wholesalers" }] }
  end

  def create_tree(account)
    account.add(:acc1, Name: 'Widget Factory')
    account.embed('Contacts', 'Contact') do |contacts|
      contacts.add(:contact1,
                   FirstName: 'John',
                   LastName: 'Smith',
                   Email: 'test@restforce.com')
      contacts.embed("Objects", "Object") do |obj|
        obj.add(:obj1, accountId: '@{acc1.Id}')
      end
    end
    account.add(:acc2,
                Name: 'Width Wholesalers')
  end

  let(:response) do
    {
      hasErrors: false,
      results: [{
        referenceId: "acc1",
        id: "001D000000K0fXOIAZ"
      }, {
        referenceId: "contact1",
        id: "001D000000K0fXPIAZ"
      }, {
        referenceId: "obj1",
        id: "003D000000QV9n2IAD"
      }, {
        referenceId: "acc2",
        id: "003D000000QV9n3IAD"
      }]
    }
  end

  let(:response_with_error) do
    {
      hasErrors: true,
      results: [{
        referenceId: "contact1",
        errors: [{
          statusCode: "INVALID_EMAIL_ADDRESS",
          message: "Email: invalid email address: 123",
          fields: ["Email"]
        }]
      }]
    }
  end

  describe "#composite_tree" do
    it "posts to the endpoint with the tree created" do
      client.
        should_receive(:api_post).
        with(endpoint, expected_tree.to_json).
        and_return(Hashie::Mash.new(body: response))

      client.composite_tree('Account') do |account|
        create_tree(account)
      end
    end

    it "should raise when given both records and a block" do
      client.should_not_receive(:api_post)

      expect do
        client.composite_tree('Account', [{ attributes: { type: 'Account' } }]) do |a|
          a.add(:acc1, Name: 'Never Sent')
        end
      end.to raise_error(ArgumentError, /records or a block/)
    end

    it "should raise when records is not an array" do
      client.should_not_receive(:api_post)

      expect do
        client.composite_tree('Account', { attributes: { type: 'Account' } })
      end.to raise_error(ArgumentError, /Array/)
    end

    it "should raise when there is nothing to send" do
      client.should_not_receive(:api_post)

      expect do
        client.composite_tree('Account')
      end.to raise_error(ArgumentError, /no records/)
    end

    it "should raise when there are more records than Salesforce accepts" do
      client.should_not_receive(:api_post)

      max = Restforce::Concerns::SObjectTreeAPI::MAX_RECORDS
      expect do
        client.composite_tree('Account') do |account|
          (max + 1).times { |i| account.add(:"acc#{i}", Name: "Account #{i}") }
        end
      end.to raise_error(ArgumentError, /#{max}/)
    end
  end

  describe "#composite_tree!" do
    let(:failed_response) do
      {
        hasErrors: true,
        results: [
          { referenceId: 'acc1',
            errors: [{ statusCode: 'INVALID_FIELD', message: 'no such field',
                       fields: ['Bogus__c'] }] }
        ]
      }
    end

    def post_and_return(body)
      client.should_receive(:api_post).and_return(Hashie::Mash.new(body: body))

      client.composite_tree!('Account') { |accounts| accounts.add(:acc1, Name: 'X') }
    end

    it "should raise when Salesforce rolled the tree back" do
      expect { post_and_return(failed_response) }.
        to raise_error(Restforce::CompositeAPIError, /INVALID_FIELD/)
    end

    it "should return the results when the tree was created" do
      expect(post_and_return(response).hasErrors).to be_falsey
    end
  end

  describe Restforce::Concerns::SObjectTreeAPI::TreeBuilder do
    subject { Restforce::Concerns::SObjectTreeAPI::TreeBuilder }
    it "takes a root" do
      expect do
        subject.new
      end.to raise_error(ArgumentError)
    end

    describe "reference id format" do
      it "should accept a symbol of legal characters" do
        expect { subject.new('Account').add(:acc1, Name: 'X') }.not_to raise_error
      end

      it "should accept a leading digit" do
        expect { subject.new('Account').add('1acc', Name: 'X') }.not_to raise_error
      end

      it "should refuse a hyphen" do
        expect { subject.new('Account').add(:'my-ref', Name: 'X') }.
          to raise_error(ArgumentError, /reference id/i)
      end

      it "should refuse a leading underscore" do
        expect { subject.new('Account').add('_acc', Name: 'X') }.
          to raise_error(ArgumentError, /reference id/i)
      end
    end

    describe "reference id uniqueness" do
      it "should refuse the same id twice at one level" do
        builder = subject.new('Account')
        builder.add(:ref1, Name: 'First')

        expect { builder.add(:ref1, Name: 'Second') }.
          to raise_error(ArgumentError, /already in use/)
      end

      it "should refuse an id already used further up the tree" do
        builder = subject.new('Account')
        builder.add(:ref1, Name: 'Account')

        expect do
          builder.embed('Contacts', 'Contact') { |c| c.add(:ref1, LastName: 'Smith') }
        end.to raise_error(ArgumentError, /already in use/)
      end

      it "should refuse an id already used in a sibling branch" do
        builder = subject.new('Account')
        builder.add(:acc1, Name: 'First')
        builder.embed('Contacts', 'Contact') { |c| c.add(:con1, LastName: 'Smith') }
        builder.add(:acc2, Name: 'Second')

        expect do
          builder.embed('Contacts', 'Contact') { |c| c.add(:con1, LastName: 'Jones') }
        end.to raise_error(ArgumentError, /already in use/)
      end

      it "should treat a symbol and its string as the same id" do
        builder = subject.new('Account')
        builder.add(:ref1, Name: 'First')

        expect { builder.add('ref1', Name: 'Second') }.
          to raise_error(ArgumentError, /already in use/)
      end

      it "should allow distinct ids throughout" do
        builder = subject.new('Account')

        expect do
          builder.add(:acc1, Name: 'First')
          builder.embed('Contacts', 'Contact') { |c| c.add(:con1, LastName: 'Smith') }
          builder.add(:acc2, Name: 'Second')
        end.not_to raise_error
      end
    end

    describe "#embed" do
      it "should raise when there is no record to embed into" do
        expect do
          subject.new('Account').embed('Contacts', 'Contact') do |contacts|
            contacts.add(:c1, LastName: 'Smith')
          end
        end.to raise_error(ArgumentError, /add a record/)
      end

      it "should raise when nested deeper than Salesforce allows" do
        nest = lambda do |builder, level|
          builder.add(:"r#{level}", Name: "level #{level}")
          builder.embed("Children", "L#{level + 1}") do |child|
            nest.call(child, level + 1)
          end
        end

        expect { nest.call(subject.new('L1'), 1) }.
          to raise_error(ArgumentError, /levels deep/)
      end
    end

    describe "#tree" do
      it "should return a bare bone record hash when empty" do
        expect(subject.new('Account').tree).to eq({ records: [] })
      end

      it "should return a a record when populated" do
        tree = subject.new('Account').tap do |account|
          create_tree(account)
        end.tree

        expect(tree).to eq(expected_tree)
      end
    end
  end
end
