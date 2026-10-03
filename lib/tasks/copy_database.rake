namespace :sakuya do
  desc "Copies all the data into another empty database with the schema loaded (e.g. from SQLite to PostgreSQL)"
  task :copy_database, [ :url ] => :environment do |_, args|
    abort "Usage: bin/rails \"sakuya:copy_database[postgres://user:password@server/database]\"" if args[:url].blank?
    tables = DatabaseCopy.copy!(args[:url], notify: ->(line) { puts line })
    puts "Done: #{tables} tables copied and row counts match."
  rescue DatabaseCopy::Error => e
    abort "Nothing was copied: #{e.message}"
  end
end
