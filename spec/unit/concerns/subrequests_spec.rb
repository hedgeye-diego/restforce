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

  # These are the only resources with no path of their own: their url comes
  # from the block define_generic_subrequest runs, which is what Base's :url
  # requirement exists to catch when it is missing.
  describe "the generic describe subrequests" do
    subject(:subrequests) do
      Restforce::Concerns::SubRequests::CompositeSubrequests.new(options)
    end

    {
      get_approval_layouts: %w[GET approvalLayouts],
      describe_approval_layouts: %w[HEAD approvalLayouts],
      get_layout_description: %w[GET layouts],
      describe_layout_description: %w[HEAD layouts]
    }.each do |method, (verb, segment)|
      it "should build a url for ##{method}" do
        subrequests.public_send(method, 'Account', 'ref1')

        expect(subrequests.requests.last).to eq(
          method: verb,
          url: "/services/data/v58.0/sobjects/Account/describe/#{segment}/",
          referenceId: 'ref1'
        )
      end
    end
  end

  describe "reference id format" do
    subject(:subrequests) do
      Restforce::Concerns::SubRequests::CompositeSubrequests.new(options)
    end

    %w[ref1 1ref my_ref R].each do |legal|
      it "should accept #{legal.inspect}" do
        expect { subrequests.find('Account', legal, '001xx') }.not_to raise_error
      end
    end

    { 'my-ref' => 'a hyphen', '_ref' => 'a leading underscore',
      'ref 1' => 'a space', 'ref#1' => 'a hash', '' => 'being empty' }.each do |bad, why|
      it "should refuse #{bad.inspect}, having #{why}" do
        expect { subrequests.find('Account', bad, '001xx') }.
          to raise_error(ArgumentError, /reference id/i)
      end
    end
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
