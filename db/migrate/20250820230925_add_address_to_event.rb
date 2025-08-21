class AddAddressToEvent < ActiveRecord::Migration[8.0]
  def change
    add_column :events, :address, :string
  end
end
