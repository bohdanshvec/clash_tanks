class AddCharacteristicsToTechniques < ActiveRecord::Migration[8.1]
  def change
    add_column :techniques, :technique_type, :string, null: false
    add_column :techniques, :attack_range, :integer, null: false
    add_column :techniques, :movement_count, :integer, null: false
    add_column :techniques, :movement_type, :string, null: false
  end
end
