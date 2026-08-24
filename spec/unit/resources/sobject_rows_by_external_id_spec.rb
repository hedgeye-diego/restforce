# frozen_string_literal: true

require 'spec_helper'
require_relative 'shared_examples'

describe Restforce::Resources::SObjectRowsByExternalId do
  describe "#to_hash" do
    it_behaves_like 'an class that takes an optional body',
                    Restforce::Resources::SObjectRowsByExternalId
  end

  describe ".build_option_url" do
    it_behaves_like 'build_option_url',
                    Restforce::Resources::SObjectRowsByExternalId,
                    {
                      sobject_name: 'Contact',
                      api_version: '50',
                      field_value: 'foo@bar.com',
                      field_name: 'Email'
                    },
                    "/services/data/v50/sobjects/Contact/Email/foo%40bar.com"
  end

  describe ".path" do
    subject(:path) do
      described_class.path('50', 'Contact', 'External_Id__c', field_value)
    end

    context "when the field value contains url structural characters" do
      let(:field_value) { 'a/b?c#d e' }

      it "should not let the value escape its own path segment" do
        expect(path).to eq(
          "/services/data/v50/sobjects/Contact/External_Id__c/a%2Fb%3Fc%23d%20e"
        )
      end
    end

    context "when the field value is a reference id" do
      let(:field_value) { '@{c1.Email}' }

      it "should leave the reference id syntax intact" do
        expect(path).to eq(
          "/services/data/v50/sobjects/Contact/External_Id__c/@{c1.Email}"
        )
      end
    end
  end
end
