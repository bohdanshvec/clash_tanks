class AddAuthenticationToPlayers < ActiveRecord::Migration[8.1]
  def change
    add_column :players, :email, :string
    add_column :players, :name, :string
    add_column :players, :password_digest, :string

    add_index :players, :email, unique: true
  end
end
