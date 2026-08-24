# frozen_string_literal: true

require 'spec_helper'

describe Restforce::Concerns::SubRequests do
  let(:options) { { api_version: '58.0' } }

  shared_examples_for "a subrequest collection" do |clazz|
    subject(:subrequests) { clazz.new(options) }

    it "should start with no requests" do
      expect(subrequests.requests).to be_empty
    end

    it "should start with an empty reference id set, not nil" do
      expect(subrequests.reference_ids).to be_empty
    end

    it "should record the reference id of each subrequest" do
      subrequests.find('Account', 'ref1', '001xx1')
      subrequests.find('Account', 'ref2', '001xx2')

      expect(subrequests.reference_ids.to_a).to eq(%w[ref1 ref2])
      expect(subrequests.requests.length).to be(2)
    end

    it "should refuse a reference id that is already in use" do
      subrequests.find('Account', 'ref1', '001xx1')

      expect { subrequests.find('Account', 'ref1', '001xx2') }.
        to raise_error(ArgumentError, /already in use/)
    end

    it "should expose update_by_id" do
      expect(subrequests).to respond_to(:update_by_id)
    end
  end

  describe Restforce::Concerns::SubRequests::GraphSubrequests do
    it_behaves_like "a subrequest collection",
                    Restforce::Concerns::SubRequests::GraphSubrequests
  end

  describe Restforce::Concerns::SubRequests::CompositeSubrequests do
    it_behaves_like "a subrequest collection",
                    Restforce::Concerns::SubRequests::CompositeSubrequests
  end

  describe Restforce::Concerns::SubRequests::UniqueNameSet do
    subject(:names) { described_class.new('reference_id') }

    it "should keep the order things were added in" do
      names << 'a'
      names << 'b'

      expect(names.to_a).to eq(%w[a b])
    end

    it "should name itself in the error it raises" do
      names << 'a'

      expect { names << 'a' }.
        to raise_error(ArgumentError, 'The reference_id a is already in use.')
    end

    it "should return itself so adds can be chained" do
      expect(names << 'a').to be(names)
    end
  end
end
