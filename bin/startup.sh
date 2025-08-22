#!/bin/bash

# GlitchCube Rails Startup Script
# This script handles all startup tasks for the GlitchCube Rails application

set -e  # Exit on any error

# Configuration
APP_ROOT="/Users/eristmini/glitchcube_rails"
RUBY_VERSION="3.3.9"
RAILS_ENV="production"
LOG_FILE="/Users/eristmini/glitchcube_rails/log/startup.log"
PID_FILE="/Users/eristmini/glitchcube_rails/tmp/pids/server.pid"
PORT=4567

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOG_FILE"
}

error() {
    echo -e "${RED}[$(date '+%Y-%m-%d %H:%M:%S')] ERROR:${NC} $1" | tee -a "$LOG_FILE"
}

success() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] SUCCESS:${NC} $1" | tee -a "$LOG_FILE"
}

warn() {
    echo -e "${YELLOW}[$(date '+%Y-%m-%d %H:%M:%S')] WARNING:${NC} $1" | tee -a "$LOG_FILE"
}

# Create log directory if it doesn't exist
mkdir -p "$(dirname "$LOG_FILE")"
mkdir -p "$(dirname "$PID_FILE")"

log "🚀 Starting GlitchCube Rails application startup..."

# Change to application directory
cd "$APP_ROOT" || {
    error "Failed to change to application directory: $APP_ROOT"
    exit 1
}

# Check if already running
if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        warn "Application appears to be already running (PID: $PID)"
        log "Stopping existing process..."
        kill "$PID" 2>/dev/null || true
        sleep 3
        # Force kill if still running
        if ps -p "$PID" > /dev/null 2>&1; then
            kill -9 "$PID" 2>/dev/null || true
            sleep 2
        fi
    fi
    rm -f "$PID_FILE"
fi

# Set up environment
export RAILS_ENV="$RAILS_ENV"
export BUNDLE_GEMFILE="$APP_ROOT/Gemfile"

# Check Ruby version
log "🔍 Checking Ruby version..."
if command -v rbenv >/dev/null 2>&1; then
    eval "$(rbenv init -)"
    if ! rbenv versions | grep -q "$RUBY_VERSION"; then
        error "Ruby $RUBY_VERSION not installed via rbenv"
        exit 1
    fi
    rbenv local "$RUBY_VERSION"
    success "Ruby $RUBY_VERSION is available"
else
    warn "rbenv not found, using system Ruby"
fi

# Check if PostgreSQL is running
log "🐘 Checking PostgreSQL status..."
if ! pgrep -x "postgres" > /dev/null; then
    log "Starting PostgreSQL..."
    if command -v brew >/dev/null 2>&1; then
        brew services start postgresql || {
            error "Failed to start PostgreSQL via brew"
            exit 1
        }
    else
        error "PostgreSQL not running and brew not available"
        exit 1
    fi
    # Wait for PostgreSQL to start
    sleep 5
fi

# Test PostgreSQL connection
if ! psql -h localhost -U postgres -c "SELECT 1;" >/dev/null 2>&1; then
    # Try with the eristmini user
    if ! psql -h localhost -U eristmini -c "SELECT 1;" >/dev/null 2>&1; then
        error "Cannot connect to PostgreSQL"
        exit 1
    fi
fi
success "PostgreSQL is running and accessible"

# Install/update gems
log "💎 Installing gems..."
if ! command -v bundle >/dev/null 2>&1; then
    gem install bundler
fi

bundle install --deployment --without development test || {
    error "Failed to install gems"
    exit 1
}
success "Gems installed successfully"

# Set up database
log "🗄️ Setting up database..."

# Create database if it doesn't exist
bundle exec rails db:create 2>/dev/null || true

# Check if migrations need to be run
if bundle exec rails db:migrate:status | grep -q "down"; then
    log "Running pending migrations..."
    bundle exec rails db:migrate || {
        error "Failed to run migrations"
        exit 1
    }
    success "Migrations completed"
else
    log "No pending migrations"
fi

# Precompile assets if needed (for production)
if [ "$RAILS_ENV" = "production" ]; then
    log "🎨 Checking if assets need precompilation..."
    if [ ! -d "public/assets" ] || [ "app/assets" -nt "public/assets" ]; then
        log "Precompiling assets..."
        bundle exec rails assets:precompile || {
            error "Failed to precompile assets"
            exit 1
        }
        success "Assets precompiled"
    else
        log "Assets are up to date"
    fi
fi

# Clear tmp/cache if it exists
if [ -d "tmp/cache" ]; then
    log "🧹 Clearing tmp/cache..."
    rm -rf tmp/cache/*
fi

# Ensure log directory exists and has proper permissions
mkdir -p log
chmod 755 log

# Start the Rails server
log "🚂 Starting Rails server on port $PORT..."
export PORT="$PORT"

# Start server in background
bundle exec rails server -e "$RAILS_ENV" -p "$PORT" -d || {
    error "Failed to start Rails server"
    exit 1
}

# Wait a moment and check if server started
sleep 3

if [ -f "$PID_FILE" ]; then
    PID=$(cat "$PID_FILE")
    if ps -p "$PID" > /dev/null 2>&1; then
        success "🎉 GlitchCube Rails server started successfully!"
        success "Server running on port $PORT (PID: $PID)"
        success "Environment: $RAILS_ENV"
        
        # Test the health endpoint
        sleep 2
        if curl -s "http://localhost:$PORT/health" > /dev/null; then
            success "Health check passed - server is responding"
        else
            warn "Health check failed - server may still be starting up"
        fi
    else
        error "Server process not found after startup"
        exit 1
    fi
else
    error "PID file not created - server may have failed to start"
    exit 1
fi

log "✅ Startup complete! Check log/production.log for application logs"
log "📊 Conversation logs available at log/conversation_production.log"