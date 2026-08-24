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

  # Internal: An external id field on the sobject under test, discovered from
  # its describe rather than hardcoded, since which field exists differs from
  # org to org. Returns nil when the org has none.
  def external_id_field
    return @external_id_field if defined?(@external_id_field)

    @external_id_field =
      client.describe(sobject)['fields'].
      reject { |field| field['name'] == 'Id' }.
      find { |field| field['externalId'] || field['idLookup'] }&.
      fetch('name')
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
  def cleanup!(tracked)
    Array(tracked).reverse_each { |type, id| destroy_quietly(type, id) }
    sweep!
  end

  def destroy_quietly(type, id)
    return if id.nil?

    client.destroy(type, id)
  rescue Restforce::NotFoundError
    # already gone, usually cascaded from its parent
  rescue StandardError => e
    warn "[smoke] could not clean up #{type} #{id}: #{e.class}"
  end

  # Internal: Deletes anything still carrying this example's nonce.
  def sweep!
    { sobject => 'Name', 'Contact' => 'LastName' }.each do |type, field|
      client.query(
        "SELECT Id FROM #{type} WHERE #{field} LIKE '%#{nonce}%'"
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
