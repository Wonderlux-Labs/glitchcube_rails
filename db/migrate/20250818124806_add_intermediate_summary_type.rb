class AddIntermediateSummaryType < ActiveRecord::Migration[8.0]
  def change
    # Add comment to document the intermediate summary type addition
    # The Summary model will handle the new 'intermediate' type in SUMMARY_TYPES constant
    # This migration serves as documentation for the schema change

    # No database changes needed - just updating the model constant
    # But adding this migration for version tracking and deployment clarity
  end
end
