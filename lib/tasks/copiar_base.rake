namespace :sakuya do
  desc "Copia todos los datos a otra base vacía con el esquema cargado (p. ej. de SQLite a PostgreSQL)"
  task :copiar_base, [ :url ] => :environment do |_, args|
    abort "Uso: bin/rails \"sakuya:copiar_base[postgres://usuario:clave@servidor/base]\"" if args[:url].blank?
    tablas = CopiaBase.copiar!(args[:url], avisar: ->(linea) { puts linea })
    puts "Listo: #{tablas} tablas copiadas y cuadradas."
  rescue CopiaBase::Error => e
    abort "No se copió: #{e.message}"
  end
end
