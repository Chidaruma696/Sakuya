require "test_helper"

class DatabaseCopyTest < ActiveSupport::TestCase
  # No transaction: Rails would also put the destination connection inside it and nothing would be
  # committed. That is why the test creates no data in the source; it copies the fixtures, which are
  # already committed.
  self.use_transactional_tests = false

  setup do
    @route = Rails.root.join("tmp", "copy_#{Process.pid}.sqlite3")
    FileUtils.rm_f(@route)
    environment = { "DATABASE_URL" => "sqlite3:#{@route}", "RAILS_ENV" => "test", "DISABLE_DATABASE_ENVIRONMENT_CHECK" => "1" }
    assert system(environment, "bin/rails", "db:schema:load", out: File::NULL, err: File::NULL), "the destination schema was not loaded"
  end

  teardown { FileUtils.rm_f(@route) }

  test "copies everything, in order, and it adds up; a destination with data is left alone" do
    lines = []
    tables = DatabaseCopy.copy!("sqlite3:#{@route}", notify: ->(l) { lines << l })
    assert_operator tables, :>, 30
    assert_includes lines, "branches: #{Branch.count}"
    assert lines.index { |l| l.start_with?("roles:") } < lines.index { |l| l.start_with?("users:") }, "first what they depend on"
    DatabaseCopy::Destination.establish_connection("sqlite3:#{@route}")
    assert_equal Product.order(:id).pluck(:key), DatabaseCopy::Destination.connection.select_values("SELECT key FROM products ORDER BY id")
    DatabaseCopy::Destination.remove_connection
    assert_match "already has data", assert_raises(DatabaseCopy::Error) { DatabaseCopy.copy!("sqlite3:#{@route}") }.message
  end
end
