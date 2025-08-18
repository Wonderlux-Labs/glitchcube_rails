# frozen_string_literal: true

namespace :processes do
  desc "Kill all Puma processes"
  task :kill_puma do
    puts "Killing all Puma processes..."
    system("pkill -f puma")
    sleep 2

    # Force kill any remaining
    system("pkill -9 -f puma 2>/dev/null")
    puts "Puma processes killed"
  end

  desc "Kill all SolidQueue processes"
  task :kill_solidqueue do
    puts "Killing all SolidQueue processes..."
    system("pkill -f solid-queue")
    sleep 2

    # Force kill any remaining
    system("pkill -9 -f solid-queue 2>/dev/null")
    system("pkill -9 -f 'bin/jobs' 2>/dev/null")
    puts "SolidQueue processes killed"
  end

  desc "Kill all Ruby processes (nuclear option)"
  task :kill_all_ruby do
    puts "WARNING: Killing ALL Ruby processes..."
    system("killall -9 ruby 2>/dev/null || true")
    puts "All Ruby processes killed"
  end

  desc "Kill all app processes (Puma + SolidQueue)"
  task kill_all: [ :kill_puma, :kill_solidqueue ] do
    puts "All application processes killed"
  end

  desc "Check running processes"
  task :status do
    puts "=== Puma Processes ==="
    system("ps aux | grep -E 'puma' | grep -v grep || echo 'No Puma processes running'")

    puts "\n=== SolidQueue Processes ==="
    system("ps aux | grep -E 'solid-queue|bin/jobs' | grep -v grep || echo 'No SolidQueue processes running'")

    puts "\n=== Database Connections ==="
    db_name = Rails.application.config.database_configuration[Rails.env]["database"] rescue "glitchcube_rails_production"
    system("psql -d postgres -c \"SELECT count(*), application_name FROM pg_stat_activity WHERE datname LIKE '%glitchcube%' GROUP BY application_name;\" 2>/dev/null || echo 'Could not check database connections'")
  end

  desc "Clean up stale PID files"
  task :cleanup_pids do
    puts "Cleaning up stale PID files..."
    %w[tmp/pids/server.pid tmp/pids/puma.pid].each do |pidfile|
      if File.exist?(pidfile)
        File.delete(pidfile)
        puts "Removed #{pidfile}"
      end
    end
    puts "PID cleanup complete"
  end
end
