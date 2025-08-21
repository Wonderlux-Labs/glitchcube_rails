class Fact < ApplicationRecord
  vectorsearch

  after_save :upsert_to_vectorsearch
end
