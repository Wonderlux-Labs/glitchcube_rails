# Production Deployment Guide

## Quick Commands

### Start/Stop Application
```bash
# Start everything (migrations, processes, health check)
./bin/prod

# Stop everything gracefully  
./bin/stop
```

### Database Management
```bash
# Setup all databases (primary, cache, queue)
bundle exec rake db:setup_all

# Recreate all databases
bundle exec rake db:recreate_all

# Individual database management
bundle exec rake db:cache:create
bundle exec rake db:cache:recreate
bundle exec rake db:queue:create  
bundle exec rake db:queue:recreate
```

### Process Management
```bash
# Kill all processes
bundle exec rake processes:kill_all

# Kill specific processes
bundle exec rake processes:kill_puma
bundle exec rake processes:kill_solidqueue

# Check status
bundle exec rake processes:status

# Nuclear option (kills ALL Ruby processes)
bundle exec rake processes:kill_all_ruby
```

## Database Configuration

The application uses three separate PostgreSQL databases:

- **Primary**: `glitchcube_rails_production` (application data)
- **Cache**: `glitchcube_rails_production_cache` (SolidCache)  
- **Queue**: `glitchcube_rails_production_queue` (SolidQueue jobs)

## Logging

- **Application**: `log/production.log`
- **SolidQueue**: `log/solid_queue.log` (separate log file)
- **Puma**: `log/puma.stdout.log`, `log/puma.stderr.log`

## Production Deployment Process

The `./bin/prod` script handles:

1. 🔥 Kill existing processes
2. 🗄️ Clear database connections
3. 🔄 Run pending migrations
4. 🗄️ Setup cache/queue databases
5. 🎨 Precompile assets (production only)
6. 🚀 Start Puma server
7. 🚀 Start SolidQueue workers
8. 🏥 Perform health checks
9. 📊 Show status

## Manual Process Management

If you need manual control:

```bash
# Start Puma
bundle exec puma -C config/puma.rb -d

# Start SolidQueue  
bundle exec rake solid_queue:start

# Check health
curl http://localhost:4567/health
```

## Troubleshooting

### Database Connection Issues
```bash
# Check database connections
bundle exec rake processes:status

# Kill database connections manually
psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname LIKE '%glitchcube%';"
```

### Process Issues
```bash
# Check what's running
ps aux | grep -E "(puma|solid-queue)"

# Kill specific PIDs
kill -TERM <PID>  # Graceful
kill -KILL <PID>  # Force
```

### Log Investigation
```bash
# Application logs
tail -f log/production.log

# SolidQueue logs (separate file)
tail -f log/solid_queue.log

# Combined view
tail -f log/production.log log/solid_queue.log
```

## Environment Variables

Key variables for production:

```bash
RAILS_ENV=production
DATABASE_URL=postgresql://...  # Or individual DB config
JOB_CONCURRENCY=4              # SolidQueue worker processes
```

## Health Monitoring

The application exposes a health endpoint:
- URL: `http://localhost:4567/health`
- Returns: JSON with database, migration, and service status
- Used by: Home Assistant health monitoring

## Emergency Procedures

### Complete Reset
```bash
./bin/stop
bundle exec rake db:recreate_all
./bin/prod
```

### Nuclear Option (Kill Everything)
```bash
bundle exec rake processes:kill_all_ruby
killall -9 ruby  # If rake doesn't work
```