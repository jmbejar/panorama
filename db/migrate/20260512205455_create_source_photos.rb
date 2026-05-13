class CreateSourcePhotos < ActiveRecord::Migration[8.1]
  def change
    create_table :source_photos do |t|
      t.references :panorama_project, null: false, foreign_key: { on_delete: :cascade }
      t.integer :position, null: false
      t.string :filename
      t.string :content_type
      t.integer :width
      t.integer :height
      t.bigint :file_size
      t.text :exif_data
      t.string :validation_status
      t.text :validation_warnings

      t.timestamps
    end

    add_index :source_photos, [ :panorama_project_id, :position ], unique: true
  end
end
