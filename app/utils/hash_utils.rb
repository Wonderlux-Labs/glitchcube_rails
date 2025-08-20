# app/utils/hash_utils.rb
# Global utility for consistent hash key handling
# Since we control all code and JSON only returns strings, let's be consistent
module HashUtils
  # Get value from hash using string key, with fallback to symbol key
  def self.get(hash, key)
    return nil unless hash.is_a?(Hash)
    
    string_key = key.to_s
    symbol_key = key.to_sym
    
    hash[string_key] || hash[symbol_key]
  end
  
  # Set value in hash using string key only (normalize all keys to strings)
  def self.set(hash, key, value)
    return unless hash.is_a?(Hash)
    hash[key.to_s] = value
  end
  
  # Convert all keys to strings (our standard format since JSON uses strings)
  def self.stringify_keys(hash)
    return hash unless hash.is_a?(Hash)
    
    hash.transform_keys(&:to_s)
  end
  
  # Convert keys to symbols only when needed for Ruby method calls
  def self.symbolize_keys(hash)
    return hash unless hash.is_a?(Hash)
    
    hash.transform_keys { |key| key.is_a?(String) ? key.to_sym : key }
  end
  
  # Safe dig that tries both string and symbol keys
  def self.dig(hash, *keys)
    return nil unless hash.is_a?(Hash)
    
    current = hash
    keys.each do |key|
      if current.is_a?(Hash)
        current = get(current, key)
      else
        return nil
      end
    end
    current
  end
end