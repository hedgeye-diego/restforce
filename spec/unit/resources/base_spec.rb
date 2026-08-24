# frozen_string_literal: true

require 'spec_helper'

describe Restforce::Resources::Base do
  describe ".build_option_url" do
    let(:url) { '/services/data/v58.0/limits' }

    it "should default the api_version" do
      expect(described_class.build_option_url(url: url)[:api_version]).to eq('26.0')
    end

    it "should let a passed in api_version win" do
      options = described_class.build_option_url(url: url, api_version: '58.0')
      expect(options[:api_version]).to eq('58.0')
    end

    it "should require a url, having no path of its own to build one from" do
      expect { described_class.build_option_url }.
        to raise_error(ArgumentError, /url/)
    end

    it "should keep the url it was given" do
      options = described_class.build_option_url(url: '/services/data/v58.0/limits')
      expect(options[:url]).to eq('/services/data/v58.0/limits')
    end
  end

  describe "#url" do
    it "should read the url out of opts" do
      resource = described_class.new(:get, url: '/services/data/v58.0/limits')
      expect(resource.url).to eq('/services/data/v58.0/limits')
    end

    it "should be nil rather than raising when opts carries no url" do
      expect(described_class.new(:get).url).to be_nil
    end
  end

  describe "#to_request" do
    it "should raise an ArgumentError without a reference id" do
      resource = described_class.new(:get, url: '/services/data/v58.0/limits')

      expect { resource.to_request }.
        to raise_error(ArgumentError, /reference id/)
    end

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
