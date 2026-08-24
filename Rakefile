# frozen_string_literal: true

require "bundler/gem_tasks"
require 'rspec/core/rake_task'

desc "Run specs"
RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'spec/**/*_spec.rb'
  # Smoke specs talk to a real Salesforce org. They are opt in, never part of
  # the default run - see spec/smoke/README.md.
  t.exclude_pattern = 'spec/smoke/**/*_spec.rb'
end

RSpec::Core::RakeTask.new(:smoke_run) do |t|
  t.pattern = 'spec/smoke/**/*_spec.rb'
end

desc "Run smoke specs against a real Salesforce org (creates and deletes records)"
task :smoke do
  ENV['RESTFORCE_SMOKE'] = '1'
  Rake::Task['smoke_run'].invoke
end

task default: [:spec]
