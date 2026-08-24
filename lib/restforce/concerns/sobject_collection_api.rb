# frozen_string_literal: true

require 'restforce/concerns/verbs'

module Restforce
  module Concerns
    module SObjectCollectionAPI
      extend Restforce::Concerns::Verbs

      define_verbs :post, :patch, :delete

      # The most records Salesforce accepts in one sObject Collections create,
      # update, upsert or delete request.
      MAX_RECORDS = 200

      # Public: Retrieves records of one sobject type in a single request,
      # returning only the fields asked for.
      #
      # Unlike the write operations this is not capped at MAX_RECORDS. The ids
      # travel in the query string, so Salesforce documents the ceiling as
      # "approximately 800 IDs before the URL length causes the HTTP 414 error
      # URI too long" - a soft limit we deliberately don't enforce.
      #
      # sobject_name - The String name of the sobject, ie 'Account'.
      # ids          - An Array of Salesforce ids to retrieve.
      # fields       - An Array of field names to return for each record.
      #
      # Examples
      #
      #   client.collection_get('Account', %w[001xx1 001xx2], %w[Id Name])
      #   # => [#<Restforce::Mash Id="001xx1" Name="Widget Factory">, ...]
      #
      # Raises ArgumentError if either ids or fields is empty.
      #
      # Returns an Array of records, in the order the ids were given.
      def collection_get(sobject_name, ids, fields)
        raise ArgumentError, "ids are required" if Array(ids).empty?
        raise ArgumentError, "fields are required" if Array(fields).empty?

        api_get("composite/sobjects/#{sobject_name}",
                ids: ids.join(','),
                fields: fields.join(',')).body
      end

      # Public: Deletes up to 200 records in a single request.
      #
      # ids  - An Array of Salesforce ids to delete.
      # opts - The Hash options used to refine the request.
      #        :all_or_none - If true, the entire request rolls back when any
      #                       record fails. (default: false)
      #
      # Examples
      #
      #   client.collection_delete(%w[001xx1 001xx2])
      #   # => [#<Restforce::Mash id="001xx1" success=true errors=[]>, ...]
      #
      # Raises ArgumentError if ids is empty or holds more than MAX_RECORDS.
      # Raises Restforce::ResponseError if :all_or_none is set and any record
      # failed.
      #
      # Returns an Array of per-record results.
      def collection_delete(ids, opts = {})
        all_or_none = opts.fetch(:all_or_none, false)
        raise ArgumentError, "ids are required" if Array(ids).empty?

        if Array(ids).length > MAX_RECORDS
          raise ArgumentError, "Cannot have more than #{MAX_RECORDS} records."
        end

        results = api_delete("composite/sobjects",
                             ids: ids.join(','),
                             allOrNone: all_or_none).body
        CollectionResponse.new(results, all_or_none: all_or_none).response
        results
      end

      # Public: Deletes records, rolling the whole request back if any one of
      # them fails.
      #
      # ids - Salesforce ids to delete, as separate arguments or an Array.
      #
      # Examples
      #
      #   client.collection_delete!('001xx1', '001xx2')
      #   client.collection_delete!(%w[001xx1 001xx2])
      #
      # Raises Restforce::ResponseError if any record failed.
      #
      # Returns an Array of per-record results.
      def collection_delete!(*ids)
        collection_delete(ids.flatten, all_or_none: true)
      end

      # Public: Creates up to 200 records in a single request.
      #
      # opts - The Hash options used to refine the request.
      #        :all_or_none - If true, the entire request rolls back when any
      #                       record fails. (default: false)
      #        :dry_run     - If true, returns the records that would be sent
      #                       without making a request. (default: false)
      #
      # Yields a RecordsBuilder to collect the records to create.
      #
      # Examples
      #
      #   client.collection_create do |records|
      #     records.add('Account', Name: 'Widget Factory')
      #     records.add('Contact', LastName: 'Smith')
      #   end
      #   # => [#<Restforce::Mash id="001xx1" success=true errors=[]>, ...]
      #
      # Raises ArgumentError if no records were added, or if more than
      # MAX_RECORDS were.
      # Raises Restforce::ResponseError if :all_or_none is set and any record
      # failed.
      #
      # Returns an Array of per-record results, or the Array of built records
      # when :dry_run is set.
      def collection_create(opts = {}, &)
        submit_records(:api_post, 'composite/sobjects', 'created', opts, &)
      end

      # Public: Creates records, rolling the whole request back if any one of
      # them fails. Equivalent to collection_create with :all_or_none set.
      #
      # See collection_create.
      def collection_create!(opts = {}, &)
        collection_create(opts.merge(all_or_none: true), &)
      end

      # Public: Updates up to 200 existing records in a single request. Each
      # record must carry its Salesforce id.
      #
      # opts - The Hash options used to refine the request.
      #        :all_or_none - If true, the entire request rolls back when any
      #                       record fails. (default: false)
      #        :dry_run     - If true, returns the records that would be sent
      #                       without making a request. (default: false)
      #
      # Yields a RecordsBuilder to collect the records to update.
      #
      # Examples
      #
      #   client.collection_update do |records|
      #     records.add('Account', id: '001xx1', Name: 'Widget Factory')
      #   end
      #   # => [#<Restforce::Mash id="001xx1" success=true errors=[]>]
      #
      # Raises ArgumentError if no records were added, or if more than
      # MAX_RECORDS were.
      # Raises Restforce::ResponseError if :all_or_none is set and any record
      # failed.
      #
      # Returns an Array of per-record results, or the Array of built records
      # when :dry_run is set.
      def collection_update(opts = {}, &)
        submit_records(:api_patch, 'composite/sobjects', 'updated', opts, &)
      end

      # Public: Updates records, rolling the whole request back if any one of
      # them fails. Equivalent to collection_update with :all_or_none set.
      #
      # See collection_update.
      def collection_update!(opts = {}, &)
        collection_update(opts.merge(all_or_none: true), &)
      end

      # Public: Creates or updates up to 200 records in a single request,
      # matching existing records on an external id field. Every record must
      # carry that field.
      #
      # sobject_type - The String name of the sobject, ie 'Account'.
      # field_name   - The String name of the external id field. It must have
      #                the External ID attribute set in Salesforce.
      # opts         - The Hash options used to refine the request.
      #                :all_or_none - If true, the entire request rolls back
      #                               when any record fails. (default: false)
      #                :dry_run     - If true, returns the records that would
      #                               be sent without making a request.
      #                               (default: false)
      #
      # Yields a RecordsBuilder to collect the records to upsert.
      #
      # Examples
      #
      #   client.collection_upsert('Account', 'MyExtId__c') do |records|
      #     records.add('Account', MyExtId__c: 'a1', Name: 'Widget Factory')
      #   end
      #   # => [#<Restforce::Mash id="001xx1" success=true created=true>]
      #
      # Raises ArgumentError if no records were added, if more than
      # MAX_RECORDS were, or if any record is missing the external id field.
      # Raises Restforce::ResponseError if :all_or_none is set and any record
      # failed.
      #
      # Returns an Array of per-record results, or the Array of built records
      # when :dry_run is set.
      def collection_upsert(sobject_type, field_name, opts = {}, &)
        submit_records(:api_patch,
                       "composite/sobjects/#{sobject_type}/#{field_name}",
                       'upserted',
                       opts,
                       RecordsBuilder.new(field_name.to_sym),
                       &)
      end

      # Public: Upserts records, rolling the whole request back if any one of
      # them fails. Equivalent to collection_upsert with :all_or_none set.
      #
      # See collection_upsert.
      def collection_upsert!(sobject_type, field_name, opts = {}, &)
        collection_upsert(sobject_type, field_name, opts.merge(all_or_none: true), &)
      end

      private

      # Internal: Collects records from the caller's block and submits them to
      # one of the composite sObject Collections endpoints.
      #
      # http_method - The api verb to send the request with, ie :api_post.
      # path        - The endpoint to submit the records to.
      # action      - Past tense name of the operation ('created', 'updated',
      #               'upserted'), used in the error raised for an empty
      #               collection.
      # opts        - Supports :all_or_none and :dry_run.
      # builder     - The RecordsBuilder yielded to the caller's block.
      #
      # Returns the results, having raised on a failed all_or_none request.
      def submit_records(http_method, path, action, opts,
                         builder = RecordsBuilder.new)
        all_or_none = opts.fetch(:all_or_none, false)
        yield(builder)
        return builder.records if opts[:dry_run]

        if builder.records.empty?
          raise ArgumentError, "There are no records to be #{action}"
        end

        if builder.records.length > MAX_RECORDS
          raise ArgumentError, "Cannot have more than #{MAX_RECORDS} records."
        end

        results = send(http_method, path,
                       { allOrNone: all_or_none, records: builder.records }).body
        CollectionResponse.new(results, all_or_none: all_or_none).response
      end

      class CollectionResponse
        attr_accessor :results, :all_or_none

        def initialize(results, all_or_none: false)
          @results = results
          @all_or_none = all_or_none
        end

        def response
          has_errors = results.any? { |result| !result.success }
          if all_or_none && has_errors
            last_error_index = results.rindex do |result|
              !result.success && !result.errors.empty? &&
                result.errors.last.statusCode != 'ALL_OR_NONE_OPERATION_ROLLED_BACK'
            end
            last_error = results[last_error_index]
            raise ::Restforce::ResponseError.new(last_error.errors.last.message, results)
          end
          results
        end
      end

      class RecordsBuilder
        attr_accessor :records, :required_field

        def initialize(required_field = nil)
          @records = []
          @required_field = required_field
        end

        # Public: Adds one record to the collection being built.
        #
        # sobject_type - The String name of the sobject, ie 'Account'.
        # opts         - The Hash of field names and values for the record.
        #                An update needs an :id; an upsert needs the external
        #                id field the request was opened with.
        #
        # Examples
        #
        #   records.add('Account', Name: 'Widget Factory')
        #
        # Raises ArgumentError if the required external id field is missing.
        #
        # Returns the Array of records built so far.
        def add(sobject_type, opts = {})
          if required_field_missing?(opts)
            raise ArgumentError, "Missing required field #{required_field}"
          end

          records << {
            attributes: { type: sobject_type }
          }.merge(opts)
        end

        def required_field_missing?(opts = {})
          required_field &&
            opts.keys.find { |k, _| k.to_s.casecmp(required_field.to_s).zero? }.nil?
        end
      end
    end
  end
end
