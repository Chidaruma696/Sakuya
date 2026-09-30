class Usuario < ApplicationRecord
  belongs_to :rol
  belongs_to :sucursal

  has_secure_password

  IDIOMAS = %w[es en de].freeze
  TEMAS = %w[sistema claro oscuro].freeze
  DENSIDADES = %w[normal compacta].freeze
  LETRAS = %w[chica normal grande].freeze

  validates :nombre, presence: true
  validates :idioma, inclusion: { in: IDIOMAS }
  validates :tema, inclusion: { in: TEMAS }
  validates :densidad, inclusion: { in: DENSIDADES }
  validates :letra, inclusion: { in: LETRAS }
  validates :usuario, presence: true, uniqueness: true,
                      format: { with: /\A[a-z0-9._-]+\z/, message: ->(*) { I18n.t("errores.usuario.formato") } }

  has_many :cargos, dependent: :restrict_with_error

  scope :activos, -> { where(activo: true) }

  def puede?(clave)
    activo && rol.permite?(clave)
  end


  def to_s
    nombre
  end
end
