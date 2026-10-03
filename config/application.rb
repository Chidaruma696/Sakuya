require_relative "boot"

require "rails/all"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Sakuya
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # A single source of time. TODO: the time zone defaults to Mexico City; let the business choose
    # it at setup. The system starts in English; each user switches it to Spanish or German. Whatever
    # is missing in a language falls back to English, the default.
    config.time_zone = "America/Mexico_City"
    config.active_record.default_timezone = :utc
    config.i18n.default_locale = :en
    config.i18n.available_locales = [ :es, :en, :de ]
    config.i18n.fallbacks = [ :en ]

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")
  end
end
