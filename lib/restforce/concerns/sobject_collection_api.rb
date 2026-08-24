# frozen_string_literal: true

require 'restforce/concerns/verbs'

module Restforce
  module Concerns
    module SObjectCollectionAPI
      extend Restforce::Concerns::Verbs

      define_verbs :post, :patch, :delete

      # sObject Collections is documented as "available in API version 42.0
      # and later". SObjectTreeAPI has no guard of its own because Salesforce
      # does not state a floor for that resource.
      MIN_API_VERSION = 42.0

      # The most records Salesforce accepts in one sObject Collections create,
      # update, upsert or delete request. SObjectTreeAPI has a limit of its
      # own that happens to be the same number - the two are unrelated and
      # move independently.
      MAX_RECORDS = 200

      # Public: Retrieves records of one sobject type in a single request,
      # returning only the fields asked for.
      #
      # Unlike the write operations this is not capped at MAX_RECORDS. The ids
      # travel in the query string, so Salesforce documents the ceiling as
      # "approximately 800 IDs before the URL length causes the HTTP 414 error
      # URI too long" - a soft limit we deliberately don't enforce.
      #
      # sobject - The String name of the sobject, ie 'Account'.
      # ids     - An Array of Salesforce ids to retrieve.
      # fields  - An Array of field names to return for each record.
      #
      # Examples
      #
      #   client.collection_get('Account', %w[001xx1 001xx2], %w[Id Name])
      #   # => [#<Restforce::Mash Id="001xx1" Name="Widget Factory">, ...]
      #
      # Raises ArgumentError if either ids or fields is empty.
      #
      # Returns an Array of records, in the order the ids were given.
      def collection_get(sobject, ids, fields)
        guard_api_version!
        raise ArgumentError, "ids are required" if Array(ids).empty?
        raise ArgumentError, "fields are required" if Array(fields).empty?

        api_get("composite/sobjects/#{sobject}",
                ids: join_for_query(ids, 'ids'),
                fields: join_for_query(fields, 'fields')).body
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
        guard_api_version!
        all_or_none = opts.fetch(:all_or_none, false)
        ids = Array(ids)
        raise ArgumentError, "ids are required" if ids.empty?

        if ids.length > MAX_RECORDS
          raise ArgumentError, "Cannot have more than #{MAX_RECORDS} records."
        end

        results = api_delete("composite/sobjects",
                             ids: join_for_query(ids, 'ids'),
                             allOrNone: all_or_none).body
        CollectionResponse.new(results, all_or_none: all_or_none).response
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
      # Returns an Array of per-record results.
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
      # Returns an Array of per-record results.
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
      # sobject    - The String name of the sobject, ie 'Account'.
      # field_name - The String name of the external id field. It must have
      #              the External ID attribute set in Salesforce.
      # opts       - The Hash options used to refine the request.
      #              :all_or_none - If true, the entire request rolls back
      #                             when any record fails. (default: false)
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
      # Returns an Array of per-record results.
      def collection_upsert(sobject, field_name, opts = {}, &)
        submit_records(:api_patch,
                       "composite/sobjects/#{sobject}/#{field_name}",
                       'upserted',
                       opts,
                       RecordsBuilder.new(field_name.to_sym),
                       &)
      end

      # Public: Upserts records, rolling the whole request back if any one of
      # them fails. Equivalent to collection_upsert with :all_or_none set.
      #
      # See collection_upsert.
      def collection_upsert!(sobject, field_name, opts = {}, &)
        collection_upsert(sobject, field_name, opts.merge(all_or_none: true), &)
      end

      # Public: Builds the request body collection_create would post, without
      # sending anything. Validates exactly as collection_create does, so an
      # empty or oversized collection raises here too.
      #
      # opts - The Hash options used to refine the request.
      #        :all_or_none - Carried into the body. (default: false)
      #
      # Yields a RecordsBuilder to collect the records.
      #
      # Examples
      #
      #   client.collection_create_request do |records|
      #     records.add('Account', Name: 'Widget Factory')
      #   end
      #   # => { allOrNone: false,
      #   #      records: [{ attributes: { type: 'Account' },
      #   #                  Name: 'Widget Factory' }] }
      #
      # Returns the Hash body that would be posted.
      def collection_create_request(opts = {}, &)
        build_records_request('created', opts, &)
      end

      # Public: Builds the request body collection_update would post, without
      # sending anything.
      #
      # See collection_create_request.
      def collection_update_request(opts = {}, &)
        build_records_request('updated', opts, &)
      end

      # Public: Builds the request body collection_upsert would post, without
      # sending anything.
      #
      # The sobject type is accepted so the signature matches
      # collection_upsert - copying a call and appending _request should not
      # silently shift the arguments - but it identifies the endpoint rather
      # than anything in the body, so it does not appear in the result.
      #
      # See collection_create_request.
      def collection_upsert_request(_sobject, field_name, opts = {}, &)
        build_records_request('upserted', opts, RecordsBuilder.new(field_name.to_sym), &)
      end

      private

      # Internal: Refuses the call when the client is pinned to an api version
      # older than the resource, so it fails here with something readable
      # rather than at Salesforce with a 404.
      #
      # Raises Restforce::APIVersionError if the version is too old.
      #
      # Returns nothing.
      def guard_api_version!
        Restforce::Concerns::API.version_guard(MIN_API_VERSION,
                                               options[:api_version])
      end

      # Internal: Joins values into the comma delimited list these endpoints
      # expect, refusing any value that already holds the delimiter. Such a
      # value would otherwise arrive at Salesforce as two.
      #
      # Raises ArgumentError if any value contains a comma.
      #
      # Returns the String list.
      def join_for_query(values, name)
        offender = values.find { |value| value.to_s.include?(',') }
        if offender
          raise ArgumentError, "#{name} cannot contain a comma: #{offender.inspect}"
        end

        values.join(',')
      end

      # Internal: Collects records from the caller's block and submits them to
      # one of the composite sObject Collections endpoints.
      #
      # http_method - The api verb to send the request with, ie :api_post.
      # path        - The endpoint to submit the records to.
      # action      - Past tense name of the operation ('created', 'updated',
      #               'upserted'), used in the error raised for an empty
      #               collection.
      # opts        - Supports :all_or_none.
      # builder     - The RecordsBuilder yielded to the caller's block.
      #
      # Returns the results, having raised on a failed all_or_none request.
      def submit_records(http_method, path, action, opts,
                         builder = RecordsBuilder.new, &)
        body = build_records_request(action, opts, builder, &)
        results = send(http_method, path, body).body
        CollectionResponse.new(results, all_or_none: body[:allOrNone]).response
      end

      # Internal: Collects the caller's records and validates them, returning
      # the request body without sending anything. Shared by the command
      # methods and the *_request queries, so both validate identically.
      #
      # Raises ArgumentError if the collection is empty or oversized.
      #
      # Returns the Hash body that would be posted.
      def build_records_request(action, opts, builder = RecordsBuilder.new)
        guard_api_version!
        yield(builder)

        if builder.records.empty?
          raise ArgumentError, "There are no records to be #{action}"
        end

        if builder.records.length > MAX_RECORDS
          raise ArgumentError, "Cannot have more than #{MAX_RECORDS} records."
        end

        { allOrNone: opts.fetch(:all_or_none, false), records: builder.records }
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
