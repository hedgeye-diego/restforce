# frozen_string_literal: true

require 'spec_helper'
require_relative 'shared_examples'

describe Restforce::Resources::SObjectRows do
  describe "#to_hash" do
    it_behaves_like 'an class that takes an optional body',
                    Restforce::Resources::SObjectRows

    it "should have a 'httpHeaders' when passed in" do
      object = Restforce::Resources::SObjectRows.new(:delete,
                                                     sobject_name: 'Account',
                                                     http_headers: {
                                                       "If-Modified-Since" =>
                                                         'Mon, 30 Nov 2020 08:34:54 MST.'
                                                     },
                                                     url: "url")
      expect(object.to_hash).to eql({
                                      method: 'DELETE',
                                      url: 'url',
                                      httpHeaders: {
                                        "If-Modified-Since" =>
                                          'Mon, 30 Nov 2020 08:34:54 MST.'
                                      }
                                    })
    end
  end

  describe ".build_option_url" do
    it_behaves_like 'build_option_url',
                    Restforce::Resources::SObjectRows,
                    { sobject_name: 'Account',
                      api_version: '50',
                      id: '123' },
                    "/services/data/v50/sobjects/Account/123"

    context "when fields are requested" do
      subject(:options) do
        Restforce::Resources::SObjectRows.build_option_url(
          sobject_name: 'Account', api_version: '50', id: '123',
          fields: %w[Id Name]
        )
      end

      it "should put the fields in the query string" do
        expect(options[:url]).
          to eq("/services/data/v50/sobjects/Account/123?fields=Id%2CName")
      end

      it "should consume the fields option while building the url" do
        expect(options).not_to have_key(:fields)
      end
    end
  end
end
