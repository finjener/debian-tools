# Configuration Guide

The Debian Tools GUI supports configuration via files and environment variables.

## Configuration File

**Location**: `~/.config/debian-tools/config.toml`

```toml
# Custom paths
scripts_dir = "/path/to/scripts"
log_dir = "/path/to/logs"
backup_dir = "/path/to/backups"

# Script execution settings
default_timeout_minutes = 30

# Pre-execution checks
check_network = true
check_disk_space = true
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `scripts_dir` | path | auto-detected | Override scripts directory |
| `log_dir` | path | `~/.local/share/debian-tools/logs` | Log file location |
| `backup_dir` | path | `~/.local/share/debian-tools/backups` | Backup storage |
| `default_timeout_minutes` | integer | 30 | Script timeout |
| `check_network` | boolean | true | Check network before scripts |
| `check_disk_space` | boolean | true | Check disk space before scripts |

## Environment Variables

Environment variables override config file settings:

| Variable | Override |
|----------|----------|
| `DEBIAN_TOOLS_CONFIG` | Config file path |
| `DEBIAN_TOOLS_SCRIPTS_DIR` | Scripts directory |
| `DEBIAN_TOOLS_LOG_DIR` | Log directory |
| `DT_LOG_DIR` | Log directory (legacy) |

## Preferences

User preferences are automatically saved to `~/.config/debian-tools/preferences.json`:
- Theme selection
- Last selected category
- Window size (future)

## Example

```bash
# Set custom scripts directory for this session
export DEBIAN_TOOLS_SCRIPTS_DIR=/opt/my-scripts
debian-tools-gui
```
