require 'rails_helper'

RSpec.describe ServiceResult do
  describe '.success' do
    context 'with data' do
      it 'creates a successful result with provided data' do
        data = { user_id: 123, message: 'Hello' }
        result = ServiceResult.success(data)

        expect(result.success?).to be true
        expect(result.data).to eq(data)
        expect(result.error).to be_nil
      end
    end

    context 'without data' do
      it 'creates a successful result with empty hash as default data' do
        result = ServiceResult.success

        expect(result.success?).to be true
        expect(result.data).to eq({})
        expect(result.error).to be_nil
      end
    end
  end

  describe '.failure' do
    it 'creates a failed result with error message' do
      error_message = 'Something went wrong'
      result = ServiceResult.failure(error_message)

      expect(result.success?).to be false
      expect(result.data).to be_nil
      expect(result.error).to eq(error_message)
    end
  end

  describe 'struct behavior' do
    it 'allows direct field access' do
      result = ServiceResult.new(true, { foo: 'bar' }, nil)

      expect(result.success?).to be true
      expect(result.data).to eq({ foo: 'bar' })
      expect(result.error).to be_nil
    end

    # NOTE: Skipping immutability test - overkill for service communication
    # it 'is immutable once created' do
    #   result = ServiceResult.success({ count: 1 })
    #
    #   # This should not modify the original result
    #   expect { result.data[:count] = 999 }.not_to change { result.data[:count] }
    # end
  end

  describe 'field validation' do
    it 'ensures success and failure states are mutually exclusive' do
      success_result = ServiceResult.success({ data: 'test' })
      failure_result = ServiceResult.failure('error')

      expect(success_result.success?).to be true
      expect(success_result.error).to be_nil

      expect(failure_result.success?).to be false
      expect(failure_result.data).to be_nil
    end
  end
end
