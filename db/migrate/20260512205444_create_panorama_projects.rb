class CreatePanoramaProjects < ActiveRecord::Migration[8.1]
  def change
    create_table :panorama_projects do |t|
      t.string :title, null: false
      t.string :status, null: false, default: "draft"
      t.datetime :processing_started_at
      t.datetime :processing_finished_at
      t.text :failure_reason
      t.string :stitching_engine
      t.text :stitching_logs

      t.timestamps
    end

    add_index :panorama_projects, :status
  end
end
