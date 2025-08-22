require 'rails_helper'

RSpec.describe Fact, type: :model do
  # This model is essentially a data holder with vectorsearch functionality
  # No custom business logic to test beyond basic ActiveRecord functionality

  it 'is a valid ActiveRecord model' do
    expect(Fact.new).to be_a(ApplicationRecord)
  end

  it 'includes vectorsearch functionality' do
    expect(Fact.ancestors.map(&:to_s)).to include('Vectorsearch')
  end
end
