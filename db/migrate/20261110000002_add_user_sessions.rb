# Sessions as rows: each user holds as many as their limit (one unless the administrator says
# otherwise), each one ends on its own, and an offline sale keeps who uploaded it when that was
# not whoever sold it.
class AddUserSessions < ActiveRecord::Migration[8.1]
  def change
    create_table :user_sessions do |t|
      t.references :user, null: false, foreign_key: true
      t.string :token_digest, null: false
      t.datetime :started_at, null: false
      t.datetime :last_used_at, null: false
      t.string :device
    end

    add_column :users, :session_limit, :integer, null: false, default: 1
    add_check_constraint :users, "session_limit BETWEEN 1 AND 5", name: "users_session_limit"

    add_reference :sales, :uploaded_by, foreign_key: { to_table: :users }
  end
end
