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

  describe "a subclass that builds its own url" do
    let(:resource) do
      Class.new(described_class) do
        class << self
          def url_options
            [:api_version]
          end

          def path(api_version)
            "/services/data/v#{api_version}/limits"
          end
        end
      end
    end

    it "should not inherit Base's url requirement" do
      expect(resource.required_options).not_to include(:url)
    end

    it "should build its url from path rather than demand one" do
      expect(resource.build_option_url(api_version: '58.0')[:url]).
        to eq('/services/data/v58.0/limits')
    end
  end

  describe "an option that is not there" do
    it "should raise rather than answer nil" do
      resource = described_class.new(:get, url: '/x')

      expect { resource.send(:no_such_option) }.to raise_error(NameError)
    end

    it "should answer an option that is there" do
      resource = described_class.new(:get, url: '/x', body: { Name: 'Widget' })

      expect(resource.send(:body)).to eq(Name: 'Widget')
    end
  end

  describe "visibility" do
    it "should keep the method_missing hooks private" do
      expect(described_class.private_instance_methods).
        to include(:method_missing, :respond_to_missing?)
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
