# frozen_string_literal: true

# Counts ActiveRecord SQL queries executed inside a block, so specs can guard
# against N+1 regressions:
#
#   expect { User.all.map(&:posts) }.not_to exceed_query_limit(1)
#
# Schema introspection, cached queries, and transaction-control statements
# (BEGIN/COMMIT/ROLLBACK/SAVEPOINT) are ignored so the count reflects real
# data-loading queries only.
RSpec::Matchers.define :exceed_query_limit do |expected|
  supports_block_expectations

  match do |block|
    @query_count = count_queries(&block)
    @query_count > expected
  end

  failure_message do |_block|
    "expected more than #{expected} queries, but #{@query_count} were executed"
  end

  failure_message_when_negated do |_block|
    "expected at most #{expected} queries, but #{@query_count} were executed"
  end

  def count_queries(&block)
    count = 0
    ignore = /\A\s*(BEGIN|COMMIT|ROLLBACK|SAVEPOINT|RELEASE)/i
    counter = lambda do |_name, _start, _finish, _id, payload|
      next if %w[CACHE SCHEMA].include?(payload[:name])
      next if payload[:sql] =~ ignore

      count += 1
    end
    ActiveSupport::Notifications.subscribed(counter, "sql.active_record", &block)
    count
  end
end
