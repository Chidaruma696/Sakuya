# Moves all the data in this database into another empty one with the same schema (for example,
# from SQLite to PostgreSQL when the business grows). Copies table by table, from those that depend
# on nothing to those that depend on them, resets the id counters and finally compares how many
# rows there are on each side.
#
#   bin/rails "sakuya:copy_database[postgres://user:password@server/sakuya]"
module DatabaseCopy
  class Error < StandardError; end

  BATCH = 1_000
  SKIP_TABLES = %w[schema_migrations ar_internal_metadata].freeze

  # A bare model to read and write any table in the destination.
  class Destination < ActiveRecord::Base
    self.abstract_class = true
  end

  def self.copy!(url, origin: ActiveRecord::Base.connection, notify: ->(_) { })
    Destination.establish_connection(url)
    destination = Destination.connection
    tables = sort(origin.tables - SKIP_TABLES, origin)
    missing = tables - destination.tables
    raise Error, "the destination is missing tables (load the schema first): #{missing.join(", ")}" if missing.any?
    full = tables.select { |t| destination.select_value("SELECT COUNT(*) FROM #{destination.quote_table_name(t)}").to_i.positive? }
    raise Error, "the destination already has data in: #{full.join(", ")}" if full.any?

    destination.transaction do
      tables.each do |table|
        total = copy_table(table, origin, destination)
        notify.("#{table}: #{total}")
      end
    end
    reset_sequences(tables, destination)
    compare(tables, origin, destination)
  ensure
    Destination.remove_connection
  end

  # From the tables that depend on nothing to the ones that depend on them (by their foreign keys).
  def self.sort(tables, connection)
    depends = tables.to_h { |t| [ t, connection.foreign_keys(t).map(&:to_table).uniq & tables - [ t ] ] }
    order = []
    until depends.empty?
      ready = depends.select { |_, deps| (deps - order).empty? }.keys
      raise Error, "there is a foreign key cycle among: #{depends.keys.join(", ")}" if ready.empty?
      order.concat(ready.sort)
      ready.each { |t| depends.delete(t) }
    end
    order
  end

  def self.copy_table(table, origin, destination)
    columns = origin.columns(table).map(&:name)
    order = columns.include?("id") ? " ORDER BY id" : ""
    total = 0
    from = 0
    loop do
      rows = origin.select_all("SELECT * FROM #{origin.quote_table_name(table)}#{order} LIMIT #{BATCH} OFFSET #{from}").to_a
      break if rows.empty?
      model = Class.new(Destination) { self.table_name = table }
      model.reset_column_information
      model.insert_all!(rows.map { |r| r.slice(*columns) }, record_timestamps: false)
      total += rows.size
      from += BATCH
    end
    total
  end

  # In PostgreSQL ids come from sequences: make them continue after the last one copied.
  def self.reset_sequences(tables, destination)
    return unless destination.respond_to?(:reset_pk_sequence!)
    tables.each { |t| destination.reset_pk_sequence!(t) if destination.columns(t).any? { |c| c.name == "id" } }
  end

  def self.compare(tables, origin, destination)
    different = tables.filter_map do |t|
      a = origin.select_value("SELECT COUNT(*) FROM #{origin.quote_table_name(t)}").to_i
      b = destination.select_value("SELECT COUNT(*) FROM #{destination.quote_table_name(t)}").to_i
      "#{t} (#{a} → #{b})" if a != b
    end
    raise Error, "row counts do not match: #{different.join(", ")}" if different.any?
    tables.size
  end

  private_class_method :sort, :copy_table, :reset_sequences, :compare
end
