# frozen_string_literal: true

require 'spec_helper'

describe Restforce::Resources::Base do
  describe ".build_option_url" do
    it "should default the api_version" do
      expect(described_class.build_option_url[:api_version]).to eq('26.0')
    end

    it "should let a passed in api_version win" do
      options = described_class.build_option_url(api_version: '58.0')
      expect(options[:api_version]).to eq('58.0')
    end

    it "should keep the url it was given" do
      options = described_class.build_option_url(url: '/services/data/v58.0/limits')
      expect(options[:url]).to eq('/services/data/v58.0/limits')
    end

    it "should not build a url, having no path of its own" do
      expect(described_class.build_option_url).not_to have_key(:url)
    end
  end

  describe "#to_request" do
    it "should carry the reference id through" do
      resource = described_class.new(:get,
                                     url: '/services/data/v58.0/limits',
                                     reference_id: 'ref1')

      expect(resource.to_request).to eq(
        { method: 'GET', url: '/services/data/v58.0/limits', referenceId: 'ref1' }
      )
    end
  end
end
