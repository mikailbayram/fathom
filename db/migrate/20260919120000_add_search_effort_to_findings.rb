class AddSearchEffortToFindings < ActiveRecord::Migration[8.1]
  def change
    # How hard a buyer would have to work to reach this, judged during the
    # buyer-visible check, plus the one sentence saying what they would do.
    add_column :findings, :search_effort, :string
    add_column :findings, :search_path, :text
  end
end
