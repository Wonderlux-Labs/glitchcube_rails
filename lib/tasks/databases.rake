# frozen_string_literal: true

namespace :db do
  namespace :queue do
    desc "Create the queue database"
    task create: :environment do
      config = ActiveRecord::Base.configurations.configs_for(name: "queue", env_name: Rails.env).first
      if config
        database_name = config.database
        puts "Creating queue database: #{database_name}"

        system("createdb #{database_name}") || begin
          puts "Database #{database_name} may already exist or creation failed"
        end

        # Load schema
        ActiveRecord::Base.establish_connection(config.configuration_hash)
        load Rails.root.join("db/queue_schema.rb")
        puts "Queue database schema loaded successfully!"
      else
        puts "No queue database configuration found for #{Rails.env} environment"
      end
    end

    desc "Drop and recreate the queue database"
    task recreate: :environment do
      config = ActiveRecord::Base.configurations.configs_for(name: "queue", env_name: Rails.env).first
      if config
        database_name = config.database
        puts "Dropping queue database: #{database_name}"
        system("dropdb --if-exists #{database_name}")

        puts "Recreating queue database: #{database_name}"
        Rake::Task["db:queue:create"].invoke
      else
        puts "No queue database configuration found for #{Rails.env} environment"
      end
    end

    desc "Load queue schema"
    task load_schema: :environment do
      config = ActiveRecord::Base.configurations.configs_for(name: "queue", env_name: Rails.env).first
      if config
        ActiveRecord::Base.establish_connection(config.configuration_hash)
        load Rails.root.join("db/queue_schema.rb")
        puts "Queue schema loaded successfully!"
      else
        puts "No queue database configuration found for #{Rails.env} environment"
      end
    end
  end

  namespace :cache do
    desc "Create the cache database"
    task create: :environment do
      config = ActiveRecord::Base.configurations.configs_for(name: "cache", env_name: Rails.env).first
      if config
        database_name = config.database
        puts "Creating cache database: #{database_name}"

        system("createdb #{database_name}") || begin
          puts "Database #{database_name} may already exist or creation failed"
        end

        # Load schema
        ActiveRecord::Base.establish_connection(config.configuration_hash)
        load Rails.root.join("db/cache_schema.rb")
        puts "Cache database schema loaded successfully!"
      else
        puts "No cache database configuration found for #{Rails.env} environment"
      end
    end

    desc "Drop and recreate the cache database"
    task recreate: :environment do
      config = ActiveRecord::Base.configurations.configs_for(name: "cache", env_name: Rails.env).first
      if config
        database_name = config.database
        puts "Dropping cache database: #{database_name}"
        system("dropdb --if-exists #{database_name}")

        puts "Recreating cache database: #{database_name}"
        Rake::Task["db:cache:create"].invoke
      else
        puts "No cache database configuration found for #{Rails.env} environment"
      end
    end

    desc "Load cache schema"
    task load_schema: :environment do
      config = ActiveRecord::Base.configurations.configs_for(name: "cache", env_name: Rails.env).first
      if config
        ActiveRecord::Base.establish_connection(config.configuration_hash)
        load Rails.root.join("db/cache_schema.rb")
        puts "Cache schema loaded successfully!"
      else
        puts "No cache database configuration found for #{Rails.env} environment"
      end
    end
  end

  desc "Setup all databases (primary, cache, and queue)"
  task setup_all: :environment do
    puts "Setting up all databases..."

    # Main database
    puts "Setting up primary database..."
    Rake::Task["db:create"].invoke
    Rake::Task["db:migrate"].invoke

    # Cache database
    puts "Setting up cache database..."
    Rake::Task["db:cache:create"].invoke

    # Queue database
    puts "Setting up queue database..."
    Rake::Task["db:queue:create"].invoke

    puts "All databases set up successfully!"
  end

  desc "Recreate all databases (primary, cache, and queue)"
  task recreate_all: :environment do
    puts "Recreating all databases..."

    # Drop and recreate main database
    puts "Recreating primary database..."
    Rake::Task["db:drop"].invoke
    Rake::Task["db:create"].invoke
    Rake::Task["db:migrate"].invoke

    # Recreate cache database
    puts "Recreating cache database..."
    Rake::Task["db:cache:recreate"].invoke

    # Recreate queue database
    puts "Recreating queue database..."
    Rake::Task["db:queue:recreate"].invoke

    puts "All databases recreated successfully!"
  end
end
