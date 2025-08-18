# spec/services/prompt_service_spec.rb
require 'rails_helper'

RSpec.describe PromptService do
  let(:conversation) { create(:conversation) }
  let(:persona) { 'buddy' }
  let(:extra_context) { {} }
  
  describe '.build_prompt_for' do
    subject do
      described_class.build_prompt_for(
        persona: persona,
        conversation: conversation,
        extra_context: extra_context
      )
    end
    
    it 'returns a hash with expected keys' do
      expect(subject).to be_a(Hash)
      expect(subject).to have_key(:system_prompt)
      expect(subject).to have_key(:messages)
      expect(subject).to have_key(:tools)
      expect(subject).to have_key(:context)
    end
    
    context 'when two-tier mode is disabled' do
      before do
        Rails.configuration.two_tier_tools_enabled = false
      end
      
      it 'includes tool definitions in system prompt' do
        expect(subject[:system_prompt]).to include('AVAILABLE TOOLS:')
      end
      
      it 'returns full tool definitions for persona' do
        tools = subject[:tools]
        expect(tools).to be_an(Array)
        expect(tools).not_to be_empty
        expect(tools.first).to respond_to(:name)
      end
    end
    
    context 'when two-tier mode is enabled' do
      before do
        Rails.configuration.two_tier_tools_enabled = true
      end
      
      it 'includes two-tier mode instructions instead of tool definitions' do
        expect(subject[:system_prompt]).to include('TWO-TIER MODE:')
        expect(subject[:system_prompt]).to include('Instead of calling tools directly')
        expect(subject[:system_prompt]).not_to include('AVAILABLE TOOLS:')
      end
      
      it 'includes structured output instructions with real tool categories' do
        expect(subject[:system_prompt]).to include('Tool intentions should be natural language')
        expect(subject[:system_prompt]).to include('AVAILABLE TOOL CATEGORIES:')
        # Should include actual tool categories from our real tools
        expect(subject[:system_prompt]).to include('lights')
      end
      
      it 'returns actual tool definitions for technical LLM' do
        tools = subject[:tools]
        expect(tools).to be_an(Array)
        expect(tools).not_to be_empty
        expect(tools.first).to respond_to(:name)
      end
    end
  end
  
  describe '#build_structured_output_instructions' do
    let(:service) { described_class.new(persona: persona, conversation: conversation, extra_context: extra_context) }
    
    subject { service.send(:build_structured_output_instructions) }
    
    it 'includes two-tier mode explanation' do
      expect(subject).to include('TWO-TIER MODE')
      expect(subject).to include('Instead of calling tools directly')
    end
    
    it 'lists actual available tool categories' do
      expect(subject).to include('AVAILABLE TOOL CATEGORIES:')
      # Should include real categories from our actual tool registry
      expect(subject).to include('lights')
    end
    
    it 'provides example tool intentions' do
      expect(subject).to include('Make the lights warm and golden')
      expect(subject).to include('Play something energetic')
    end
    
    it 'explains the two-tier architecture' do
      expect(subject).to include('separate technical AI will execute')
    end
  end
  
  describe '#enhance_prompt_with_context' do
    let(:service) { described_class.new(persona: persona, conversation: conversation, extra_context: extra_context) }
    let(:base_prompt) { "You are a test character." }
    
    before do
      allow(service).to receive(:load_base_system_prompt).and_return("Base system rules")
      allow(service).to receive(:build_current_context).and_return("Current context")
    end
    
    context 'when two-tier mode is disabled' do
      before do
        allow(Tools::Registry).to receive(:two_tier_mode_enabled?).and_return(false)
        allow(service).to receive(:format_tools_for_prompt).and_return("Tool list")
      end
      
      it 'includes traditional tool definitions' do
        result = service.send(:enhance_prompt_with_context, base_prompt)
        expect(result).to include("AVAILABLE TOOLS:")
        expect(result).to include("Tool list")
      end
    end
    
    context 'when two-tier mode is enabled' do
      before do
        allow(Tools::Registry).to receive(:two_tier_mode_enabled?).and_return(true)
        allow(service).to receive(:build_structured_output_instructions).and_return("Structured instructions")
      end
      
      it 'includes structured output instructions instead' do
        result = service.send(:enhance_prompt_with_context, base_prompt)
        expect(result).to include("TWO-TIER MODE:")
        expect(result).to include("Structured instructions")
        expect(result).not_to include("AVAILABLE TOOLS:")
      end
    end
  end
end