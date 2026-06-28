# app/controllers/admin/base_controller.rb

class Admin::BaseController < ApplicationController
  # Base controller for admin dashboard
  # Add any admin-wide authentication or configuration here

  before_action :set_admin_context

  private

  def set_admin_context
    @admin_nav_items = [
      { name: "Dashboard", path: admin_root_path, icon: "🏠" },
      { name: "Conversations", path: admin_conversations_path, icon: "💬" },
      { name: "Memories", path: admin_memories_path, icon: "🧠" },
      { name: "Summaries", path: admin_summaries_path, icon: "📝" },
      { name: "World State", path: admin_world_state_path, icon: "🌍" },
      { name: "Prompts", path: admin_prompts_path, icon: "🤖" },
      { name: "Jobs", path: "/jobs", icon: "⚙️" },
      { name: "System", path: admin_system_path, icon: "📊" }
    ]
  end
end
