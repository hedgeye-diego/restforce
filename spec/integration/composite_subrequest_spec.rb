# frozen_string_literal: true

require 'spec_helper'

describe Restforce::AbstractClient do
  describe 'composite subrequest urls' do
    let(:api_version) { Restforce.configuration.api_version }

    # Captures the urls Restforce actually puts on the wire, which for composite
    # subrequests live inside the POST body rather than in the request path.
    def subrequest_urls(&block)
      captured = nil

      stub_request(:post, %r{/services/data/v#{api_version}/composite}).
        with { |request| captured = JSON.parse(request.body) }.
        to_return(status: 200,
                  body: { compositeResponse: [] }.to_json,
                  headers: { 'Content-Type' => 'application/json' })

      client.composite(&block)
      captured['compositeRequest'].map { |subrequest| subrequest['url'] }
    end

    it "should contain an external id that would otherwise break the path" do
      urls = subrequest_urls do |subrequests|
        subrequests.find_by('Account', 'ref1', 'a/b?c#d e', 'External_Id__c')
      end

      expect(urls).to eq(
        ["/services/data/v#{api_version}/sobjects/Account/External_Id__c/" \
         "a%2Fb%3Fc%23d%20e"]
      )
    end

    it "should encode a space in a record id as %20, never as +" do
      urls = subrequest_urls do |subrequests|
        subrequests.find('Account', 'ref1', '001D000000 INjVe')
      end

      expect(urls.first).to end_with('001D000000%20INjVe')
      expect(urls.first).not_to include('+')
    end

    it "should leave reference id syntax intact" do
      urls = subrequest_urls do |subrequests|
        subrequests.find('Account', 'ref1', '@{ref0.records[0].Id}')
      end

      expect(urls).to eq(
        ["/services/data/v#{api_version}/sobjects/Account/@{ref0.records[0].Id}"]
      )
    end
  end
end
