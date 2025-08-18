# frozen_string_literal: true

require 'fileutils'

namespace :config do
  # Configuration constants
  REMOTE_HOST = 'root@glitch.local'
  REMOTE_CONFIG_PATH = '/config'
  LOCAL_CONFIG_PATH = 'data/homeassistant'
  
  # Sync patterns - consistent across all commands
  SYNC_EXCLUDES = [
    '--exclude=.storage',
    '--exclude=backups',
    '--exclude=tts',
    '--exclude=.cloud', 
    '--exclude=deps',
    '--exclude=llmvision',
    '--exclude=home-assistant.log*',
    '--exclude=*.db*',
    '--exclude=secrets.yaml',
    '--exclude=.DS_Store',
    '--exclude=**/__pycache__/',
    '--exclude=*.pyc',
    '--exclude=logs/',
    '--exclude=*.log'
  ].freeze

  SYNC_INCLUDES = [
    '--include=**/',                                        # Include directories for traversal
    '--include=*.yaml',                                     # Include YAML files
    '--include=*.yml',
    '--include=**/*.yaml',
    '--include=**/*.yml',
    '--include=packages/',                                  # Include packages directory
    '--include=packages/**',
    '--include=custom_components/glitchcube_conversation/', # Include only our custom component
    '--include=custom_components/glitchcube_conversation/**'
  ].freeze

  SYNC_FINAL_EXCLUDES = [
    '--exclude=custom_components/**',  # Exclude all other custom components
    '--exclude=*'                      # Exclude everything not explicitly included
  ].freeze

  # Colors for output
  RED = "\e[31m"
  GREEN = "\e[32m"
  YELLOW = "\e[33m"
  BLUE = "\e[34m"
  PURPLE = "\e[35m"
  CYAN = "\e[36m"
  RESET = "\e[0m"

  def sync_patterns
    (SYNC_EXCLUDES + load_custom_excludes + SYNC_INCLUDES + SYNC_FINAL_EXCLUDES).join(' ')
  end

  def load_custom_excludes
    excludes_file = "#{LOCAL_CONFIG_PATH}/.sync_excludes"
    return [] unless File.exist?(excludes_file)
    
    File.readlines(excludes_file)
        .map(&:strip)
        .reject(&:empty?)
        .reject { |l| l.start_with?('#') }
        .map { |p| "--exclude=#{p}" }
  end

  def dry_run?
    ENV['DRY_RUN'] == 'true'
  end

  def puts_colored(message, color = RESET)
    puts "#{color}#{message}#{RESET}"
  end

  def create_backup(description)
    return if dry_run?
    
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    backup_name = "config_backup_#{description}_#{timestamp}"
    
    puts_colored("💾 Creating backup: #{backup_name}", BLUE)
    
    # Create backup on remote
    ssh_cmd = "ssh #{REMOTE_HOST} 'cd #{REMOTE_CONFIG_PATH} && tar -czf /tmp/#{backup_name}.tar.gz --exclude=backups --exclude=home-assistant.log* --exclude=*.db* --exclude=.storage . && mkdir -p #{REMOTE_CONFIG_PATH}/backups && mv /tmp/#{backup_name}.tar.gz #{REMOTE_CONFIG_PATH}/backups/'"
    
    if system(ssh_cmd)
      puts_colored("✅ Backup created: #{backup_name}.tar.gz", GREEN)
    else
      puts_colored("⚠️  Backup creation failed - continuing anyway", YELLOW)
    end
  end

  def confirm_action(message, default = false)
    return true if dry_run?
    
    default_prompt = default ? '[Y/n]' : '[y/N]'
    print "#{message} #{default_prompt}: "
    
    response = $stdin.gets&.chomp&.downcase
    return default if response.nil? || response.empty?
    
    %w[y yes].include?(response)
  end

  def execute_rsync(description, command)
    puts_colored("#{description}...", BLUE)
    
    if dry_run?
      puts_colored("DRY RUN: #{command}", YELLOW)
      return true
    end
    
    system(command)
  end

  def ensure_local_config_dir
    FileUtils.mkdir_p(LOCAL_CONFIG_PATH) unless Dir.exist?(LOCAL_CONFIG_PATH)
  end

  # ============================================================================
  # INCREMENTAL SYNC COMMANDS (No Deletions)
  # ============================================================================

  desc 'Push only newer/modified local files to remote (no deletions)'
  task :push_newer do
    ensure_local_config_dir
    puts_colored('📤 Pushing newer local files to remote...', CYAN)
    puts_colored('(This will NOT delete any remote files)', BLUE)
    
    push_cmd = "rsync -av --update #{sync_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
    
    if execute_rsync('Pushing newer files', push_cmd)
      puts_colored('✅ Newer files pushed successfully!', GREEN)
    else
      puts_colored('❌ Push failed!', RED)
      exit 1
    end
  end

  desc 'Pull only newer/modified remote files to local (no deletions)'  
  task :pull_newer do
    ensure_local_config_dir
    puts_colored('📥 Pulling newer remote files to local...', CYAN)
    puts_colored('(This will NOT delete any local files)', BLUE)
    
    pull_cmd = "rsync -av --update #{sync_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
    
    if execute_rsync('Pulling newer files', pull_cmd)
      puts_colored('✅ Newer files pulled successfully!', GREEN)
    else
      puts_colored('❌ Pull failed!', RED) 
      exit 1
    end
  end

  desc 'Push only new local files that don\'t exist on remote'
  task :push_created do
    ensure_local_config_dir
    puts_colored('📤 Pushing new local files to remote...', CYAN)
    puts_colored('(Only files that don\'t exist remotely)', BLUE)
    
    push_cmd = "rsync -av --ignore-existing #{sync_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
    
    if execute_rsync('Pushing new files', push_cmd)
      puts_colored('✅ New files pushed successfully!', GREEN)
    else
      puts_colored('❌ Push failed!', RED)
      exit 1  
    end
  end

  desc 'Pull only new remote files that don\'t exist locally'
  task :pull_created do
    ensure_local_config_dir
    puts_colored('📥 Pulling new remote files to local...', CYAN)
    puts_colored('(Only files that don\'t exist locally)', BLUE)
    
    pull_cmd = "rsync -av --ignore-existing #{sync_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
    
    if execute_rsync('Pulling new files', pull_cmd)
      puts_colored('✅ New files pulled successfully!', GREEN)
    else
      puts_colored('❌ Pull failed!', RED)
      exit 1
    end
  end

  # ============================================================================ 
  # DELETION COMMANDS (Explicit and Safe)
  # ============================================================================

  desc 'Delete local files that don\'t exist on remote (with confirmation)'
  task :clean_local do
    ensure_local_config_dir
    puts_colored('🧹 Cleaning local files not present on remote...', CYAN)
    
    # Show what would be deleted first
    dry_run_cmd = "rsync -avn --delete #{sync_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
    dry_output = `#{dry_run_cmd} 2>&1`
    
    deletions = dry_output.lines.grep(/^deleting/).map { |l| l.sub(/^deleting /, '').strip }
    
    if deletions.empty?
      puts_colored('✅ No local files need to be cleaned!', GREEN)
      return
    end
    
    puts_colored('Files that will be DELETED locally:', YELLOW)
    deletions.each { |f| puts_colored("  ❌ #{f}", RED) }
    
    return unless confirm_action("Delete these #{deletions.count} local files?", false)
    
    clean_cmd = "rsync -av --delete #{sync_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
    
    if execute_rsync('Cleaning local files', clean_cmd)
      puts_colored("✅ Cleaned #{deletions.count} local files!", GREEN)
    else
      puts_colored('❌ Clean failed!', RED)
      exit 1
    end
  end

  desc 'Delete remote files that don\'t exist locally (with confirmation)'
  task :clean_remote do
    ensure_local_config_dir
    puts_colored('🧹 Cleaning remote files not present locally...', CYAN)
    
    create_backup('before_clean_remote')
    
    # Show what would be deleted first
    dry_run_cmd = "rsync -avn --delete #{sync_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
    dry_output = `#{dry_run_cmd} 2>&1`
    
    deletions = dry_output.lines.grep(/^deleting/).map { |l| l.sub(/^deleting /, '').strip }
    
    if deletions.empty?
      puts_colored('✅ No remote files need to be cleaned!', GREEN)
      return
    end
    
    puts_colored('Files that will be DELETED on remote:', YELLOW)
    deletions.each { |f| puts_colored("  ❌ #{f}", RED) }
    
    return unless confirm_action("Delete these #{deletions.count} remote files?", false)
    
    clean_cmd = "rsync -av --delete #{sync_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
    
    if execute_rsync('Cleaning remote files', clean_cmd)
      puts_colored("✅ Cleaned #{deletions.count} remote files!", GREEN)
    else
      puts_colored('❌ Clean failed!', RED)
      exit 1
    end
  end

  desc 'Interactive cleanup showing what would be deleted in both directions'
  task :prune do
    ensure_local_config_dir
    puts_colored('✂️  Interactive file pruning...', CYAN)
    
    # Check what would be deleted locally
    pull_dry_cmd = "rsync -avn --delete #{sync_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
    pull_output = `#{pull_dry_cmd} 2>&1`
    local_deletions = pull_output.lines.grep(/^deleting/).map { |l| l.sub(/^deleting /, '').strip }
    
    # Check what would be deleted remotely  
    push_dry_cmd = "rsync -avn --delete #{sync_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
    push_output = `#{push_dry_cmd} 2>&1`
    remote_deletions = push_output.lines.grep(/^deleting/).map { |l| l.sub(/^deleting /, '').strip }
    
    if local_deletions.empty? && remote_deletions.empty?
      puts_colored('✅ No files need pruning!', GREEN)
      return
    end
    
    if local_deletions.any?
      puts_colored("\n📂 Files that would be deleted LOCALLY:", YELLOW)
      local_deletions.each { |f| puts_colored("  ❌ #{f}", RED) }
    end
    
    if remote_deletions.any?
      puts_colored("\n🌐 Files that would be deleted REMOTELY:", YELLOW) 
      remote_deletions.each { |f| puts_colored("  ❌ #{f}", RED) }
    end
    
    puts_colored("\n🤔 What would you like to prune?", PURPLE)
    puts_colored('1) Clean local files only', BLUE)
    puts_colored('2) Clean remote files only', BLUE)
    puts_colored('3) Clean both (make them identical)', BLUE)
    puts_colored('4) Cancel', BLUE)
    
    if dry_run?
      puts_colored('DRY RUN: Would prompt for pruning choice', YELLOW)
      choice = '4'  # Default to cancel in dry run
    else
      print 'Choice [1/2/3/4]: '
      choice = $stdin.gets&.chomp
    end
    
    case choice
    when '1'
      Rake::Task['config:clean_local'].invoke if local_deletions.any?
    when '2'
      Rake::Task['config:clean_remote'].invoke if remote_deletions.any?
    when '3'
      puts_colored('🔄 Full bidirectional cleanup...', CYAN)
      create_backup('before_full_prune')
      Rake::Task['config:clean_local'].invoke if local_deletions.any?
      Rake::Task['config:clean_remote'].invoke if remote_deletions.any?
    else
      puts_colored('❌ Pruning cancelled', YELLOW)
    end
  end

  # ============================================================================
  # ADVANCED SYNC COMMANDS
  # ============================================================================

  desc 'Smart bidirectional sync with conflict detection'
  task :sync do
    ensure_local_config_dir
    puts_colored('🧠 Smart bidirectional sync with conflict detection...', CYAN)
    
    # Analyze changes in both directions
    puts_colored('🔍 Analyzing changes...', BLUE)
    
    pull_dry_cmd = "rsync -avn --delete #{sync_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
    pull_output = `#{pull_dry_cmd} 2>&1`
    
    push_dry_cmd = "rsync -avn --delete #{sync_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
    push_output = `#{push_dry_cmd} 2>&1`
    
    # Parse results
    pull_changes = pull_output.lines.grep(/^[<>cf]/).map { |l| l.split.last }.compact
    push_changes = push_output.lines.grep(/^[<>cf]/).map { |l| l.split.last }.compact
    pull_deletions = pull_output.lines.grep(/^deleting/).map { |l| l.sub(/^deleting /, '').strip }
    push_deletions = push_output.lines.grep(/^deleting/).map { |l| l.sub(/^deleting /, '').strip }
    
    has_changes = pull_changes.any? || push_changes.any? || pull_deletions.any? || push_deletions.any?
    
    unless has_changes
      puts_colored('✅ No changes detected - files are in sync!', GREEN)
      next
    end
    
    puts_colored('📊 Sync Analysis Results:', PURPLE)
    
    if pull_changes.any?
      puts_colored('📥 Would pull from remote:', BLUE)
      pull_changes.each { |f| puts_colored("  ← #{f}", CYAN) }
    end
    
    if push_changes.any?
      puts_colored('📤 Would push to remote:', BLUE) 
      push_changes.each { |f| puts_colored("  → #{f}", CYAN) }
    end
    
    if pull_deletions.any?
      puts_colored('🗑️ Would delete locally:', YELLOW)
      pull_deletions.each { |f| puts_colored("  ✗ #{f}", RED) }
    end
    
    if push_deletions.any?
      puts_colored('🗑️ Would delete on remote:', YELLOW)
      push_deletions.each { |f| puts_colored("  ✗ #{f}", RED) }
    end
    
    # Check for conflicts
    conflicts = pull_changes & push_changes
    if conflicts.any?
      puts_colored('⚠️ CONFLICTS (modified in both locations):', RED)
      conflicts.each { |f| puts_colored("  ⚡ #{f}", RED) }
      
      puts_colored('🤔 How to resolve conflicts?', PURPLE)
      puts_colored('1) Keep local changes (push to remote)', BLUE)
      puts_colored('2) Keep remote changes (pull from remote)', BLUE)
      puts_colored('3) Manual review (abort)', BLUE)
      
      if dry_run?
        puts_colored('DRY RUN: Would prompt for conflict resolution', YELLOW)
        choice = '3'  # Default to abort in dry run
      else
        print 'Choice [1/2/3]: '
        choice = $stdin.gets&.chomp
      end
      
      case choice
      when '1'
        puts_colored('📤 Keeping local - pushing changes...', CYAN)
        create_backup('before_conflict_resolution')
        push_cmd = "rsync -av --delete #{sync_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
        execute_rsync('Resolving conflicts by pushing', push_cmd)
      when '2'
        puts_colored('📥 Keeping remote - pulling changes...', CYAN)
        pull_cmd = "rsync -av --delete #{sync_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
        execute_rsync('Resolving conflicts by pulling', pull_cmd)
      else
        puts_colored('❌ Sync cancelled for manual review', YELLOW)
        next
      end
    else
      next unless confirm_action('Continue with bidirectional sync?', true)
      
      create_backup('before_bidirectional_sync')
      
      puts_colored('🔄 Performing bidirectional sync...', CYAN)
      
      # Pull first, then push
      pull_cmd = "rsync -av --update --delete #{sync_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
      push_cmd = "rsync -av --update --delete #{sync_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
      
      if execute_rsync('Pulling changes', pull_cmd) && execute_rsync('Pushing changes', push_cmd)
        puts_colored('✅ Bidirectional sync completed!', GREEN)
      else
        puts_colored('❌ Sync failed!', RED)
        exit 1
      end
    end
  end

  desc 'Make remote exactly match local (with backup)'
  task :mirror_to_remote do
    ensure_local_config_dir
    puts_colored('🪞 Mirroring local to remote (exact match)...', CYAN)
    puts_colored('⚠️  This will make remote IDENTICAL to local', YELLOW)
    
    create_backup('before_mirror_to_remote')
    
    return unless confirm_action('Make remote exactly match local?', false)
    
    mirror_cmd = "rsync -av --delete #{sync_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
    
    if execute_rsync('Mirroring to remote', mirror_cmd)
      puts_colored('✅ Remote now matches local exactly!', GREEN)
    else
      puts_colored('❌ Mirror failed!', RED)
      exit 1
    end
  end

  desc 'Make local exactly match remote (with backup)' 
  task :mirror_from_remote do
    ensure_local_config_dir
    puts_colored('🪞 Mirroring remote to local (exact match)...', CYAN)
    puts_colored('⚠️  This will make local IDENTICAL to remote', YELLOW)
    
    return unless confirm_action('Make local exactly match remote?', false)
    
    mirror_cmd = "rsync -av --delete #{sync_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
    
    if execute_rsync('Mirroring from remote', mirror_cmd)
      puts_colored('✅ Local now matches remote exactly!', GREEN)
    else
      puts_colored('❌ Mirror failed!', RED)
      exit 1
    end
  end

  # ============================================================================
  # UTILITY COMMANDS
  # ============================================================================

  desc 'Show sync status and differences between local/remote'
  task :status do
    ensure_local_config_dir
    puts_colored('📊 Configuration Sync Status', PURPLE)
    puts_colored('=' * 40, PURPLE)
    
    # Check connectivity
    if system("ssh -o ConnectTimeout=5 #{REMOTE_HOST} 'exit' 2>/dev/null")
      puts_colored("✅ Connected to #{REMOTE_HOST}", GREEN)
    else
      puts_colored("❌ Cannot connect to #{REMOTE_HOST}", RED)
      return
    end
    
    # Get file counts
    local_count = `find #{LOCAL_CONFIG_PATH} -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l`.strip.to_i
    remote_count = `ssh #{REMOTE_HOST} 'find #{REMOTE_CONFIG_PATH} -name "*.yaml" -o -name "*.yml" 2>/dev/null | wc -l' 2>/dev/null`.strip.to_i
    
    puts_colored("📁 Local YAML files: #{local_count}", BLUE)
    puts_colored("🌐 Remote YAML files: #{remote_count}", BLUE)
    
    # Check for changes
    puts_colored("\n🔍 Change Analysis:", PURPLE)
    
    pull_dry_cmd = "rsync -avn #{sync_patterns} #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/ #{LOCAL_CONFIG_PATH}/"
    pull_output = `#{pull_dry_cmd} 2>&1`
    pull_changes = pull_output.lines.grep(/^[<>cf]/).count
    
    push_dry_cmd = "rsync -avn #{sync_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"  
    push_output = `#{push_dry_cmd} 2>&1`
    push_changes = push_output.lines.grep(/^[<>cf]/).count
    
    if pull_changes.zero? && push_changes.zero?
      puts_colored('✅ Files are in sync!', GREEN)
    else
      puts_colored("📥 Files that would be pulled: #{pull_changes}", YELLOW) if pull_changes > 0
      puts_colored("📤 Files that would be pushed: #{push_changes}", YELLOW) if push_changes > 0
      puts_colored("\n💡 Run 'rake config:diff' for detailed differences", BLUE)
    end
    
    # Show last backup
    last_backup = `ssh #{REMOTE_HOST} 'ls -t #{REMOTE_CONFIG_PATH}/backups/config_backup_*.tar.gz 2>/dev/null | head -1' 2>/dev/null`.strip
    if last_backup.empty?
      puts_colored("\n📦 No backups found", YELLOW)
    else
      backup_name = File.basename(last_backup)
      backup_time = backup_name.match(/_(\d{8}_\d{6})/)&.[](1)
      if backup_time
        formatted_time = Time.strptime(backup_time, '%Y%m%d_%H%M%S').strftime('%Y-%m-%d %H:%M:%S')
        puts_colored("\n📦 Last backup: #{formatted_time}", BLUE)
      end
    end
  end

  desc 'Create timestamped backup of remote configuration'
  task :backup do
    puts_colored('💾 Creating configuration backup...', CYAN)
    
    timestamp = Time.now.strftime('%Y%m%d_%H%M%S')
    backup_name = "config_manual_backup_#{timestamp}"
    
    create_backup('manual')
    puts_colored('✅ Manual backup created!', GREEN)
    puts_colored("💡 Backups are stored in #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/backups/", BLUE)
  end

  desc 'Show detailed diff between local and remote files'
  task :diff do
    ensure_local_config_dir
    puts_colored('🔍 Detailed configuration differences...', CYAN)
    
    # Create temporary directory for comparison
    temp_dir = "/tmp/glitchcube_remote_#{Time.now.to_i}"
    FileUtils.mkdir_p(temp_dir)
    
    begin
      # Download key files for comparison
      key_files = ['configuration.yaml', 'automations.yaml', 'mqtt.yaml', 'rest_commands.yaml']
      
      key_files.each do |file|
        remote_file = "#{temp_dir}/#{file}"
        local_file = "#{LOCAL_CONFIG_PATH}/#{file}"
        
        # Download remote file
        if system("scp -q #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/#{file} #{remote_file} 2>/dev/null")
          if File.exist?(local_file)
            puts_colored("\n📄 Comparing #{file}:", PURPLE)
            
            diff_output = `diff -u #{local_file} #{remote_file} 2>/dev/null`
            if diff_output.empty?
              puts_colored('  ✅ Files are identical', GREEN)
            else
              puts_colored('  📝 Differences found:', YELLOW)
              diff_lines = diff_output.lines
              if diff_lines.count > 20
                puts diff_lines.first(20).join
                puts_colored("  ... (#{diff_lines.count - 20} more lines)", BLUE)
                puts_colored("  💡 Run 'diff -u #{local_file} #{remote_file}' for full diff", BLUE)
              else
                puts diff_output
              end
            end
          else
            puts_colored("\n📄 #{file}: Only exists on remote", YELLOW)
          end
        elsif File.exist?(local_file)
          puts_colored("\n📄 #{file}: Only exists locally", YELLOW)
        end
      end
      
      # Show rsync summary
      puts_colored("\n📊 Full rsync analysis:", PURPLE)
      dry_run_cmd = "rsync -avn --itemize-changes #{sync_patterns} #{LOCAL_CONFIG_PATH}/ #{REMOTE_HOST}:#{REMOTE_CONFIG_PATH}/"
      system(dry_run_cmd)
      
    ensure
      FileUtils.rm_rf(temp_dir)
    end
  end

  # ============================================================================
  # CONVENIENCE ALIASES
  # ============================================================================

  # Keep old command names as aliases for backward compatibility
  task :bisync => :sync
  task :smartsync => :sync
end

# Global convenience aliases
task 'config:push' => 'config:push_newer'
task 'config:pull' => 'config:pull_newer'