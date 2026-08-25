# frozen_string_literal: true

# Smoke specs run against a real Salesforce org. They are not part of the
# default spec run and never load spec_helper, which disables net connect for
# everything else.
#
# See spec/smoke/README.md for how to run them.

require 'restforce'
require 'securerandom'

module SmokeHelper
  PASSWORD_FLOW = %w[SF_USERNAME SF_PASSWORD SF_CLIENT_ID SF_CLIENT_SECRET].freeze
  TOKEN_FLOW    = %w[SF_OAUTH_TOKEN SF_INSTANCE_URL].freeze

  module_function

  # Internal: Smoke specs only run when asked for explicitly, so that a bare
  # `rspec` never reaches the network even on a machine that has credentials
  # sitting in its environment.
  def enabled?
    ENV['RESTFORCE_SMOKE'] == '1'
  end

  # Internal: Returns the reason these specs cannot run, or nil if they can.
  def unavailable_reason
    return 'set RESTFORCE_SMOKE=1 to run smoke specs (rake smoke)' unless enabled?
    return nil if present?(TOKEN_FLOW) || present?(PASSWORD_FLOW)

    "set #{PASSWORD_FLOW.join(' ')} or #{TOKEN_FLOW.join(' ')}"
  end

  def present?(names)
    names.all? { |name| !ENV.fetch(name, '').empty? }
  end

  def api_version
    ENV.fetch('SF_API_VERSION', '58.0')
  end

  def sobject
    ENV.fetch('SF_SOBJECT', 'Account')
  end

  def client
    @client ||= Restforce.new(**credentials)
  end

  def credentials
    options = { api_version: api_version }

    if present?(TOKEN_FLOW)
      options[:oauth_token]  = ENV.fetch('SF_OAUTH_TOKEN')
      options[:instance_url] = ENV.fetch('SF_INSTANCE_URL')
    else
      options[:username]       = ENV.fetch('SF_USERNAME')
      options[:password]       = ENV.fetch('SF_PASSWORD')
      options[:security_token] = ENV.fetch('SF_SECURITY_TOKEN', '')
      options[:client_id]      = ENV.fetch('SF_CLIENT_ID')
      options[:client_secret]  = ENV.fetch('SF_CLIENT_SECRET')
      options[:host]           = ENV.fetch('SF_HOST', 'login.salesforce.com')
    end

    options
  end

  def describe_fields(type = sobject)
    @describe_fields ||= {}
    @describe_fields[type] ||= client.describe(type)['fields']
  end

  # Internal: An external id field on the sobject under test, discovered from
  # its describe rather than hardcoded, since which field exists differs from
  # org to org. Returns nil when the org has none.
  def external_id_field
    return @external_id_field if defined?(@external_id_field)

    @external_id_field = external_id_candidates.first&.fetch('name')
  end

  # Internal: An external id field that will accept an arbitrary string.
  #
  # A typed field validates its contents, so Contact.Email - which is idLookup
  # in most orgs - rejects a value holding a space or a slash before the url
  # encoding it is meant to exercise is ever reached. Only a plain text field
  # can carry one.
  #
  # Returns the String field name, or nil.
  def external_id_text_field
    return @external_id_text_field if defined?(@external_id_text_field)

    @external_id_text_field =
      external_id_candidates.find { |field| field['type'] == 'string' }&.fetch('name')
  end

  # Internal: The Salesforce type of the external id field in use - 'string'
  # for a Text field, 'email' for Contact.Email, and so on.
  def external_id_field_type
    external_id_candidates.first&.fetch('type')
  end

  def external_id_candidates
    describe_fields.
      reject { |field| field['name'] == 'Id' }.
      select { |field| field['externalId'] || field['idLookup'] }
  end

  # Internal: The fields this object insists on at create time, read off its
  # describe rather than assumed - Account wants Name, Contact wants LastName,
  # and Name on Contact is a read only formula.
  #
  # Returns an Array of String field names.
  def required_text_fields(type = sobject)
    @required_text_fields ||= {}
    @required_text_fields[type] ||= begin
      required = describe_fields(type).select do |field|
        field['createable'] && !field['nillable'] &&
          !field['defaultedOnCreate'] && field['type'] == 'string'
      end

      required.map { |field| field['name'] }
    end
  end

  # Internal: The field a record's label lands in, used by the count queries.
  # Takes a type because the tree specs need a real parent-child pair and are
  # pinned to Account and Contact whatever SF_SOBJECT says.
  def label_field(type = sobject)
    required_text_fields(type).first || 'Name'
  end

  # Internal: Minimal attributes for creating a record of the object under
  # test, labelled with this example's nonce.
  #
  # Orgs often carry validation rules that describe cannot report - a required
  # FirstName on Contact, say - so SF_EXTRA_FIELDS takes a comma separated list
  # of Field=Value pairs to satisfy them.
  #
  # Returns a Hash.
  def attributes(suffix = '', type = sobject)
    attrs = required_text_fields(type).to_h do |field|
      [field.to_sym, "Restforce smoke #{nonce}#{suffix}"]
    end

    # SF_EXTRA_FIELDS satisfies validation rules on the object under test, so
    # it is not applied to the other types a spec may touch alongside it.
    return attrs unless type == sobject

    ENV.fetch('SF_EXTRA_FIELDS', '').split(',').each do |pair|
      key, value = pair.split('=', 2)
      attrs[key.strip.to_sym] = value.to_s.strip unless key.to_s.strip.empty?
    end

    attrs
  end

  # Internal: A value unique to the example being run. Per example rather than
  # per run, because several specs assert a record count by name - if two
  # examples shared a prefix, a leak in one would fail the other and the
  # failure would point at the wrong place.
  def nonce
    @nonce ||= SecureRandom.hex(4)
  end

  def reset_nonce!
    @nonce = SecureRandom.hex(4)
  end

  # Internal: Everything an example created, named with this example's nonce.
  #
  # Tracked ids cover the normal case. The sweep covers the one that matters:
  # an example asserting that nothing was created, which leaves records behind
  # precisely when it fails and has no ids to clean up with.
  #
  # Returns nothing.
  def cleanup!(tracked, pattern = nonce)
    Array(tracked).reverse_each { |type, id| destroy_quietly(type, id) }
    sweep!(pattern)
  end

  def destroy_quietly(type, id)
    return if id.nil?

    client.destroy(type, id)
  rescue Restforce::NotFoundError
    # already gone, usually cascaded from its parent
  rescue StandardError => e
    warn "[smoke] could not clean up #{type} #{id}: #{e.class}"
  end

  # Internal: The types a run can create, and the field carrying the nonce.
  # Account and Contact are here unconditionally because the tree spec needs a
  # real parent-child pair and is pinned to them regardless of SF_SOBJECT.
  def swept_types
    { sobject => 'Name', 'Account' => 'Name', 'Contact' => 'LastName' }
  end

  # Internal: Deletes anything still carrying this example's nonce.
  def sweep!(pattern = nonce)
    swept_types.each do |type, field|
      client.query(
        "SELECT Id FROM #{type} WHERE #{field} LIKE '%#{pattern}%'"
      ).each { |record| destroy_quietly(type, record.Id) }
    rescue StandardError
      # the org may not have this object, or the field may not be queryable
    end
  end
end

RSpec.configure do |config|
  config.before(:each, :smoke) do
    reason = SmokeHelper.unavailable_reason
    skip(reason) if reason

    SmokeHelper.reset_nonce!
    @created = []
  end

  # Runs whatever the outcome, and only when the example actually reached an
  # org - a skipped example has nothing to clean up and no client to do it with.
  config.after(:each, :smoke) do
    SmokeHelper.cleanup!(@created) unless SmokeHelper.unavailable_reason
  end
end
