# frozen_string_literal: true

require 'restforce/concerns/verbs'

module Restforce
  module Concerns
    module SObjectTreeAPI
      extend Restforce::Concerns::Verbs

      define_verbs :post

      # Salesforce accepts up to 200 records across all the trees in one
      # request, nested no more than five levels deep. SObjectCollectionAPI
      # has a limit of its own that happens to be the same number - the two
      # are unrelated and move independently.
      MAX_RECORDS = 200
      MAX_DEPTH = 5

      # Public: Creates a tree of up to 200 related records in a single
      # request, parents and children together.
      #
      # root    - The String name of the sobject at the root of the tree.
      # records - Prebuilt records, if you would rather assemble them
      #           yourself than use the block.
      #
      # Yields a TreeBuilder, unless prebuilt records were passed.
      #
      # Examples
      #
      #   client.composite_tree('Account') do |accounts|
      #     accounts.add(:acc1, Name: 'Widget Factory')
      #     accounts.embed('Contacts', 'Contact') do |contacts|
      #       contacts.add(:contact1, LastName: 'Smith')
      #     end
      #   end
      #
      # Raises ArgumentError if records is not an Array, if given both records
      # and a block, if there is nothing to send, or if the tree holds more
      # than MAX_RECORDS records.
      #
      # Returns the Restforce::Mash response.
      def composite_tree(root, records = [])
        unless records.is_a?(Array)
          raise ArgumentError, 'records must be an Array of record hashes.'
        end

        if block_given?
          unless records.empty?
            raise ArgumentError,
                  'Pass either records or a block to build them, not both.'
          end

          builder = TreeBuilder.new(root)
          yield(builder)
          records = builder.records
        end

        validate_tree!(records)

        api_post("composite/tree/#{root}", { records: records }.to_json).body
      end

      # Public: Creates a tree and raises if Salesforce rejected it.
      #
      # The sObject Tree resource is all or nothing, so a failure here means
      # no records were created at all.
      #
      # Raises Restforce::CompositeAPIError if the tree was rejected, and
      # everything composite_tree raises.
      #
      # Returns the Restforce::Mash response.
      def composite_tree!(root, records = [], &)
        results = composite_tree(root, records, &)
        return results unless results[:hasErrors]

        errored = (results[:results] || []).find do |result|
          result[:errors].is_a?(Array) && result[:errors].any?
        end

        raise CompositeAPIError.new(errored&.dig(:errors, 0, :statusCode), results)
      end

      private

      # Internal: Checks a built tree against the limits Salesforce documents
      # for the resource, so an oversized request fails here with something
      # readable rather than at Salesforce with something opaque.
      #
      # Returns nothing.
      def validate_tree!(records)
        raise ArgumentError, 'There are no records to send.' if records.empty?

        count = count_tree_records(records)
        return unless count > MAX_RECORDS

        raise ArgumentError, "Cannot have more than #{MAX_RECORDS} records."
      end

      # Internal: Counts every record in the tree, embedded ones included,
      # since the limit is a total across all the trees in the request.
      #
      # Returns the Integer count.
      def count_tree_records(records)
        records.sum do |record|
          1 + record.sum do |_field, value|
            embedded = value[:records] if value.is_a?(Hash)
            embedded ? count_tree_records(embedded) : 0
          end
        end
      end

      class TreeBuilder
        attr_reader :root, :records, :depth

        def initialize(root, depth = 1)
          @root = root
          @records = []
          @depth = depth
        end

        # Public: Adds one record at this level of the tree.
        #
        # reference_id - Identifies the record in the response.
        # opts         - The Hash of field names and values.
        #
        # Returns the Array of records built so far.
        def add(reference_id, opts = {})
          records << {
            attributes: { type: root, referenceId: reference_id }
          }.merge(opts)
        end

        # Public: Nests a tree of related records under the record most
        # recently added at this level.
        #
        # association - The String relationship name, ie 'Contacts'.
        # new_root    - The String sobject name of the nested records.
        #
        # Yields a TreeBuilder for the nested records.
        #
        # Raises ArgumentError if no record has been added to embed into, or
        # if the nesting would go deeper than MAX_DEPTH.
        #
        # Returns the embedded tree.
        def embed(association, new_root)
          if records.empty?
            raise ArgumentError,
                  "Cannot embed #{association} before you add a record to " \
                  "embed it into."
          end

          if depth >= MAX_DEPTH
            raise ArgumentError,
                  "Cannot nest more than #{MAX_DEPTH} levels deep."
          end

          new_builder = TreeBuilder.new(new_root, depth + 1)
          yield(new_builder)
          records.last[association] = new_builder.tree
        end

        def tree
          {
            records: records
          }
        end
      end
    end
  end
end
