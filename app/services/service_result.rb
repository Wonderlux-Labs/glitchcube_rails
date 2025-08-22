# app/services/service_result.rb
ServiceResult = Struct.new(:success?, :data, :error) do
  def self.success(data = {})
    new(true, data, nil)
  end

  def self.failure(error_message)
    new(false, nil, error_message)
  end

  def failure?
    !success?
  end
end
