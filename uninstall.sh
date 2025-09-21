#!/bin/bash
# Trunk Player Uninstall Script
# Removes all components installed by install.sh

set -e  # Exit on any error

echo "=== Trunk Player Uninstall Script ==="
echo "This script will remove all components installed by the trunk-player installer"
echo ""

# Check if running from correct directory
if [ ! -f "manage.py" ] || [ ! -f "requirements.txt" ]; then
    echo "Error: This script must be run from the trunk-player directory"
    echo "Please run: cd trunk-player && ./uninstall.sh"
    exit 1
fi

echo "WARNING: This will completely remove trunk-player and all its data!"
echo ""
echo "Components that will be removed:"
echo "- Virtual environment (venv/)"
echo "- PostgreSQL database and user (if created by installer)"
echo "- nginx configuration"
echo "- Supervisor configuration"
echo "- Generated configuration files"
echo "- Static files and directories"
echo ""

read -p "Are you sure you want to proceed? (type 'yes' to confirm): " -r
if [ "$REPLY" != "yes" ]; then
    echo "Uninstall cancelled."
    exit 0
fi

echo ""
echo "Starting uninstall process..."

# Function to safely remove files/directories
safe_remove() {
    if [ -e "$1" ]; then
        echo " Removing: $1"
        rm -rf "$1"
    fi
}

# Function to safely remove symlinks
safe_unlink() {
    if [ -L "$1" ]; then
        echo " Removing symlink: $1"
        rm -f "$1"
    fi
}

# Stop running services
echo "=== Stopping Services ==="

# Stop Django development server if running
echo "Stopping Django development server..."
pkill -f "python.*manage.py.*runserver" || true

# Stop supervisor processes
if command -v supervisorctl >/dev/null 2>&1; then
    echo "Stopping supervisor processes..."
    supervisorctl stop trunkplayer: 2>/dev/null || true
fi

# Remove virtual environment
echo ""
echo "=== Removing Virtual Environment ==="
safe_remove "venv"

# Remove generated configuration files
echo ""
echo "=== Removing Configuration Files ==="
safe_remove "trunk_player/settings_local.py"

# Remove directories created by installer
echo ""
echo "=== Removing Directories ==="
safe_remove "audio_files"
safe_remove "logs"
safe_remove "static"

# Remove database file (SQLite)
echo ""
echo "=== Removing Database Files ==="
safe_remove "db.sqlite3"

# Handle PostgreSQL cleanup
echo ""
echo "=== PostgreSQL Cleanup ==="
if command -v psql >/dev/null 2>&1; then
    echo "Checking for PostgreSQL database and user..."

    # Check if our database exists
    DB_EXISTS=false
    USER_EXISTS=false

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if psql postgres -tAc "SELECT 1 FROM pg_database WHERE datname='trunk_player';" 2>/dev/null | grep -q 1; then
            DB_EXISTS=true
        fi
        if psql postgres -tAc "SELECT 1 FROM pg_roles WHERE rolname='trunk_player_user';" 2>/dev/null | grep -q 1; then
            USER_EXISTS=true
        fi
    else
        # Linux
        if sudo -u postgres psql -tAc "SELECT 1 FROM pg_database WHERE datname='trunk_player';" 2>/dev/null | grep -q 1; then
            DB_EXISTS=true
        fi
        if sudo -u postgres psql -tAc "SELECT 1 FROM pg_roles WHERE rolname='trunk_player_user';" 2>/dev/null | grep -q 1; then
            USER_EXISTS=true
        fi
    fi

    if [ "$DB_EXISTS" = true ] || [ "$USER_EXISTS" = true ]; then
        echo ""
        echo "Found PostgreSQL components created by installer:"
        [ "$DB_EXISTS" = true ] && echo "  - Database 'trunk_player'"
        [ "$USER_EXISTS" = true ] && echo "  - User 'trunk_player_user'"
        echo ""
        read -p "Remove PostgreSQL database and user? (y/N): " -n 1 -r
        echo

        if [[ $REPLY =~ ^[Yy]$ ]]; then
            echo "Removing PostgreSQL components..."
            if [[ "$OSTYPE" == "darwin"* ]]; then
                [ "$DB_EXISTS" = true ] && psql postgres -c "DROP DATABASE IF EXISTS trunk_player;" 2>/dev/null
                [ "$USER_EXISTS" = true ] && psql postgres -c "DROP USER IF EXISTS trunk_player_user;" 2>/dev/null
            else
                [ "$DB_EXISTS" = true ] && sudo -u postgres psql -c "DROP DATABASE IF EXISTS trunk_player;" 2>/dev/null
                [ "$USER_EXISTS" = true ] && sudo -u postgres psql -c "DROP USER IF EXISTS trunk_player_user;" 2>/dev/null
            fi
            echo " PostgreSQL components removed"
        else
            echo "Keeping PostgreSQL components"
        fi
    else
        echo " No PostgreSQL components found"
    fi
else
    echo " PostgreSQL not installed - skipping database cleanup"
fi

# Remove nginx configuration
echo ""
echo "=== Removing nginx Configuration ==="
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS with Homebrew
    HOMEBREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
    NGINX_CONFIG_FILE="$HOMEBREW_PREFIX/etc/nginx/servers/trunk_player.conf"
    safe_unlink "$NGINX_CONFIG_FILE"

    # Test nginx configuration after removal
    if command -v nginx >/dev/null 2>&1; then
        echo " Testing nginx configuration..."
        if nginx -t 2>/dev/null; then
            echo " Restarting nginx..."
            brew services restart nginx 2>/dev/null || true
        else
            echo "WARNING: nginx configuration test failed after removal"
        fi
    fi
else
    # Linux
    safe_unlink "/etc/nginx/sites-enabled/trunk_player"

    # Test and restart nginx
    if command -v nginx >/dev/null 2>&1; then
        echo " Testing nginx configuration..."
        if sudo nginx -t 2>/dev/null; then
            echo " Restarting nginx..."
            sudo systemctl restart nginx 2>/dev/null || true
        else
            echo "WARNING: nginx configuration test failed after removal"
        fi
    fi
fi

# Remove supervisor configuration
echo ""
echo "=== Removing Supervisor Configuration ==="
if [[ "$OSTYPE" == "darwin"* ]]; then
    # macOS
    HOMEBREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
    SUPERVISOR_CONFIG_DIR="$HOMEBREW_PREFIX/etc/supervisor.d"
    safe_unlink "$SUPERVISOR_CONFIG_DIR/trunk_player.conf"
    safe_unlink "$SUPERVISOR_CONFIG_DIR/trunk_player.ini"

    # Update supervisor
    if command -v supervisorctl >/dev/null 2>&1; then
        echo " Updating supervisor configuration..."
        supervisorctl reread 2>/dev/null || true
        supervisorctl update 2>/dev/null || true
    fi
else
    # Linux
    safe_unlink "/etc/supervisor/conf.d/trunk_player.conf"

    # Update supervisor
    if command -v supervisorctl >/dev/null 2>&1; then
        echo " Updating supervisor configuration..."
        sudo supervisorctl reread 2>/dev/null || true
        sudo supervisorctl update 2>/dev/null || true
    fi
fi

# Remove local configuration files
echo ""
echo "=== Removing Local Configuration ==="
safe_remove "trunk_player/trunk_player.nginx"
safe_remove "trunk_player/supervisor.conf"

# Clean up temporary files
echo ""
echo "=== Cleaning Up Temporary Files ==="
safe_remove "/tmp/psql_test_error.log"
safe_remove "/tmp/db_setup.log"
safe_remove "/tmp/migration.log"

# Remove production log directory (optional)
echo ""
echo "=== Production Logs Cleanup ==="
if [[ "$OSTYPE" == "darwin"* ]]; then
    HOMEBREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
    PROD_LOG_DIR="$HOMEBREW_PREFIX/var/log/trunk-player"
    if [ -d "$PROD_LOG_DIR" ]; then
        read -p "Remove production log directory ($PROD_LOG_DIR)? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            safe_remove "$PROD_LOG_DIR"
            echo " Production logs removed"
        else
            echo " Keeping production logs"
        fi
    fi
else
    PROD_LOG_DIR="/var/log/trunk-player"
    if [ -d "$PROD_LOG_DIR" ]; then
        read -p "Remove production log directory ($PROD_LOG_DIR)? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo rm -rf "$PROD_LOG_DIR" 2>/dev/null || true
            echo " Production logs removed"
        else
            echo " Keeping production logs"
        fi
    fi
fi

echo ""
echo "=== Uninstall Summary ==="
echo ""
echo "Removed components:"
echo "✓ Virtual environment (venv/)"
echo "✓ Generated configuration files"
echo "✓ Application directories (audio_files/, logs/, static/)"
echo "✓ Database files (SQLite)"
echo "✓ nginx configuration"
echo "✓ Supervisor configuration"
echo "✓ Temporary files"

echo ""
echo "Components NOT removed (installed separately):"
echo "- Python packages installed system-wide"
echo "- PostgreSQL server (if installed by installer)"
echo "- nginx server"
echo "- Supervisor server"
echo "- System dependencies (openssl, sed, coreutils, etc.)"

# Ask about removing system binaries
echo ""
echo "=== System Dependencies Cleanup ==="
echo ""
echo "The following system packages were potentially installed by the installer:"
echo "- PostgreSQL server"
echo "- nginx web server"
echo "- supervisor process manager"
echo "- coreutils (for timeout commands)"
echo ""
echo "WARNING: These packages might be used by other applications on your system!"
echo ""
read -p "Remove all system packages installed by the installer? (y/N): " -n 1 -r
echo

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo ""
    echo "Removing system packages..."

    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS with Homebrew
        echo "Stopping services..."
        brew services stop postgresql@14 2>/dev/null || brew services stop postgresql 2>/dev/null || true
        brew services stop nginx 2>/dev/null || true
        brew services stop supervisor 2>/dev/null || true

        echo "Uninstalling packages..."

        # Remove PostgreSQL (try both versioned and unversioned)
        echo "Removing PostgreSQL..."
        if brew list | grep -q postgresql; then
            brew uninstall --ignore-dependencies --force postgresql@14 2>/dev/null || true
            brew uninstall --ignore-dependencies --force postgresql 2>/dev/null || true
            echo " PostgreSQL packages removed"
        else
            echo " PostgreSQL not installed via brew"
        fi

        # Remove other packages
        echo "Removing nginx..."
        if brew list | grep -q nginx; then
            brew uninstall --ignore-dependencies --force nginx 2>/dev/null || true
            echo " nginx package removed"
        else
            echo " nginx not installed via brew"
        fi

        echo "Removing supervisor..."
        if brew list | grep -q supervisor; then
            brew uninstall --ignore-dependencies --force supervisor 2>/dev/null || true
            echo " supervisor package removed"
        else
            echo " supervisor not installed via brew"
        fi

        echo "Removing coreutils..."
        if brew list | grep -q coreutils; then
            brew uninstall --ignore-dependencies --force coreutils 2>/dev/null || true
            echo " coreutils package removed"
        else
            echo " coreutils not installed via brew"
        fi

        # Clean up PostgreSQL data directory
        read -p "Remove PostgreSQL data directory? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            HOMEBREW_PREFIX=$(brew --prefix 2>/dev/null || echo "/opt/homebrew")
            safe_remove "$HOMEBREW_PREFIX/var/postgresql@14"
            safe_remove "$HOMEBREW_PREFIX/var/postgresql"
            echo " PostgreSQL data directory removed"
        fi

    else
        # Linux
        echo "Stopping services..."
        sudo systemctl stop postgresql 2>/dev/null || true
        sudo systemctl stop nginx 2>/dev/null || true
        sudo systemctl stop supervisor 2>/dev/null || true

        sudo systemctl disable postgresql 2>/dev/null || true
        sudo systemctl disable nginx 2>/dev/null || true
        sudo systemctl disable supervisor 2>/dev/null || true

        echo "Uninstalling packages..."

        if command -v apt >/dev/null 2>&1; then
            # Ubuntu/Debian
            sudo apt remove --purge -y postgresql postgresql-contrib postgresql-client-common postgresql-common 2>/dev/null || true
            sudo apt remove --purge -y nginx nginx-common nginx-core 2>/dev/null || true
            sudo apt remove --purge -y supervisor 2>/dev/null || true
            sudo apt autoremove -y 2>/dev/null || true
        elif command -v dnf >/dev/null 2>&1; then
            # Fedora
            sudo dnf remove -y postgresql postgresql-server postgresql-contrib 2>/dev/null || true
            sudo dnf remove -y nginx 2>/dev/null || true
            sudo dnf remove -y supervisor 2>/dev/null || true
        elif command -v yum >/dev/null 2>&1; then
            # RHEL/CentOS
            sudo yum remove -y postgresql postgresql-server postgresql-contrib 2>/dev/null || true
            sudo yum remove -y nginx 2>/dev/null || true
            sudo yum remove -y supervisor 2>/dev/null || true
        fi

        # Clean up PostgreSQL data directories
        read -p "Remove PostgreSQL data directories? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo rm -rf /var/lib/postgresql 2>/dev/null || true
            sudo rm -rf /etc/postgresql 2>/dev/null || true
            sudo rm -rf /var/log/postgresql 2>/dev/null || true
            echo " PostgreSQL data directories removed"
        fi

        # Remove users/groups created by packages
        read -p "Remove system users created by packages? (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            sudo userdel postgres 2>/dev/null || true
            sudo groupdel postgres 2>/dev/null || true
            sudo userdel nginx 2>/dev/null || true
            sudo groupdel nginx 2>/dev/null || true
            echo " System users removed"
        fi
    fi

    echo ""
    echo "System packages removal complete!"
    echo ""
    echo "Removed packages:"
    echo "✓ PostgreSQL server and data"
    echo "✓ nginx web server"
    echo "✓ supervisor process manager"
    echo "✓ coreutils (timeout commands)"

else
    echo ""
    echo "Keeping system packages installed."
    echo ""
    echo "To manually remove later, use these commands:"
    echo ""
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macOS (Homebrew):"
        echo "  brew services stop postgresql@14 nginx supervisor"
        echo "  brew uninstall postgresql@14 nginx supervisor coreutils"
    else
        echo "Ubuntu/Debian:"
        echo "  sudo systemctl stop postgresql nginx supervisor"
        echo "  sudo apt remove --purge postgresql nginx supervisor"
        echo ""
        echo "RHEL/CentOS/Fedora:"
        echo "  sudo systemctl stop postgresql nginx supervisor"
        echo "  sudo yum/dnf remove postgresql nginx supervisor"
    fi
fi

# Final verification
echo ""
echo "=== Post-Uninstall Verification ==="
echo ""

# Refresh shell command cache to ensure accurate binary detection
hash -r 2>/dev/null || true

# Check if services are still running
SERVICES_RUNNING=false

if [[ "$OSTYPE" == "darwin"* ]]; then
    if brew services list 2>/dev/null | grep -E "(postgresql|nginx|supervisor)" | grep started >/dev/null; then
        echo "Services still running:"
        brew services list | grep -E "(postgresql|nginx|supervisor)" | grep started
        SERVICES_RUNNING=true
    fi
else
    if systemctl is-active postgresql nginx supervisor 2>/dev/null | grep active >/dev/null; then
        echo "Services still running:"
        systemctl is-active postgresql nginx supervisor 2>/dev/null || true
        SERVICES_RUNNING=true
    fi
fi

if [ "$SERVICES_RUNNING" = false ]; then
    echo "✓ No trunk-player related services running"
fi

# Check if binaries still exist
BINARIES_EXIST=false
REMAINING_BINARIES=""
for binary in psql nginx supervisorctl; do
    if command -v $binary >/dev/null 2>&1; then
        echo "Binary still installed: $binary"
        BINARIES_EXIST=true
        REMAINING_BINARIES="$REMAINING_BINARIES $binary"
    fi
done

if [ "$BINARIES_EXIST" = false ]; then
    echo "✓ All related binaries removed"
else
    echo ""
    echo "Note: Some binaries are still installed. This may be because:"
    echo "- They were installed by other package managers (not Homebrew)"
    echo "- They have dependencies that prevent removal"
    echo "- They are used by other applications"
    echo ""
    echo "To manually remove remaining binaries:"
    for binary in $REMAINING_BINARIES; do
        case $binary in
            psql)
                echo "  PostgreSQL: brew uninstall --force postgresql postgresql@14"
                ;;
            nginx)
                echo "  nginx: brew uninstall --force nginx"
                ;;
            supervisorctl)
                echo "  supervisor: brew uninstall --force supervisor"
                ;;
        esac
    done
fi

echo ""
echo "=== Uninstall Complete! ==="
echo ""
echo "trunk-player has been successfully removed from your system."
echo "You can now safely delete the trunk-player directory if desired."