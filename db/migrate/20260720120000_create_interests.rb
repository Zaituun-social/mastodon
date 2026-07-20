# frozen_string_literal: true

class CreateInterests < ActiveRecord::Migration[8.0]
  def change
    create_table :interests do |t|
      t.string :name, null: false

      t.timestamps
    end

    add_index :interests, 'lower(name)', unique: true, name: :index_interests_on_name_lower

    create_table :interest_tags do |t|
      t.belongs_to :interest, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.belongs_to :tag, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :interest_tags, [:interest_id, :tag_id], unique: true

    create_table :account_interests do |t|
      t.belongs_to :account, null: false, foreign_key: { on_delete: :cascade }, index: false
      t.belongs_to :interest, null: false, foreign_key: { on_delete: :cascade }

      t.timestamps
    end

    add_index :account_interests, [:account_id, :interest_id], unique: true
  end
end
