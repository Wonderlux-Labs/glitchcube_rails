class AddVectorColumnToFacts < ActiveRecord::Migration[8.0]
  def change
    add_column :facts, :embedding, :vector,
      limit: LangchainrbRails
        .config
        .vectorsearch
        .llm
        .default_dimensions
  end
end
