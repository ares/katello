# This file should contain all the record creation needed to seed the database with its default values.
# The data can then be loaded with the rake db:seed (or created alongside the db with db:setup).
#
# !!! PLEASE KEEP THIS SCRIPT IDEMPOTENT !!!
#

def format_errors(model = nil)
  return '(nil found)' if model.nil?
  model.errors.full_messages.join(';')
end

# Proxy features
feature = Feature.where(:name => 'Pulp').first_or_create
if feature.nil? || feature.errors.any?
  fail "Unable to create proxy feature: #{format_errors feature}"
end

["Pulp", "Pulp Node"].each do |input|
  f = Feature.where(:name => input).first_or_create
  fail "Unable to create proxy feature: #{format_errors f}" if f.nil? || f.errors.any?
end
