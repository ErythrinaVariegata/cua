# macOS Lume VM Configuration Guide for cua-bench

## Overview

This guide explains how to run benchmarks using macOS Lume VMs in the cua-bench project. Lume is Apple's virtualization framework for running macOS VMs on Apple Silicon Macs.

## Table of Contents

1. [Platform Configuration](#platform-configuration)
2. [Environment Type Detection](#environment-type-detection)
3. [Running Benchmarks](#running-benchmarks)
4. [CLI Arguments](#cli-arguments)
5. [Image Management](#image-management)
6. [Configuration Files](#configuration-files)
7. [Implementation Details](#implementation-details)

---

## Platform Configuration

### What is "macos-lume"?

`macos-lume` is a **platform type** (not an environment type) defined in the cua-bench codebase. It represents macOS VMs created with Apple's Lume virtualization technology, available only on Apple Silicon Macs.

### Platform Definition

**File:** `cua_bench/cli/commands/platform.py`

**Configuration:**
```python
PLATFORMS: Dict[str, Dict[str, Any]] = {
    "macos-lume": {
        "image": None,                           # No Docker image needed
        "description": "macOS VM with Apple Virtualization (Lume, Apple Silicon only)",
        "internal_vnc_port": None,               # No VNC (native Apple VM)
        "internal_api_port": 5000,               # Standard API port
        "requires_kvm": False,                   # Uses Apple Virtualization Framework
        "image_marker": None,                    # No marker file
        "os_type": "macos",                      # Operating system type
        "boot_timeout": 120,                     # VM boot timeout in seconds
        "use_overlays": False,                   # No disk overlay needed
        "requires_apple_silicon": True,          # Only runs on Apple Silicon
    }
}
```

### Key Differences from Other Platforms

| Platform | Image Type | Virtualization | VNC | API | KVM | Apple Silicon Only |
|----------|-----------|----------------|-----|-----|-----|------------------|
| linux-docker | Container | Docker | 6901 | 8000 | No | No |
| linux-qemu | QCOW2 | QEMU/KVM | 8006 | 5000 | Yes | No |
| windows-qemu | QCOW2 | QEMU/KVM | 8006 | 5000 | Yes | No |
| android-qemu | QCOW2 | QEMU/KVM | 8006 | 5000 | Yes | No |
| **macos-lume** | **Native VM** | **Apple Virtualization** | **None** | **5000** | **No** | **Yes** |

---

## Environment Type Detection

### How env_type is Determined

**File:** `cua_bench/cli/commands/run.py` (lines 2131-2202)

The `_detect_env_type_and_image()` function determines the environment type through this priority:

1. **CLI argument (`--platform`)** - Highest priority
2. **CLI argument (`--image`)** - Derives env_type from image name
3. **Task configuration** - Reads from `task.computer.setup_config.os_type`
4. **Default fallback** - `linux-docker`

### Current Supported env_type Values

```python
# In CLI argument parser (cua_bench/cli/main.py:113-116)
parser.add_argument(
    "--platform",
    dest="platform",
    choices=["linux-docker", "linux-qemu", "windows-qemu", "android-qemu"],
    help="Platform type (auto-detected from task if not set)",
)
```

**Note:** `macos-lume` is **NOT** currently in the CLI choices! This is a gap in the implementation.

### Detection Logic

From `_detect_env_type_and_image()`:

```python
if image_name and env_type:
    return env_type, image_name

# Try to detect from task config
env = make(str(env_path))
if env.tasks_config_fn:
    tasks = env.tasks_config_fn()
    task = tasks[task_idx]
    
    if hasattr(task, "computer") and task.computer:
        computer = task.computer
        # Read os_type from task configuration
        os_type = computer.get("setup_config", {}).get("os_type")
        
        if os_type and "windows" in os_type.lower():
            env_type = "windows-qemu"
        elif os_type and "android" in os_type.lower():
            env_type = "android-qemu"
        else:
            env_type = "linux-docker"  # Default

# Defaults
env_type = env_type or "linux-docker"
image_name = image_name or env_type
return env_type, image_name
```

**Gap:** There is no detection for `macos` or `macos-lume` in the os_type checking!

---

## Running Benchmarks

### How Task Runner Uses env_type

**File:** `cua_bench/runner/task_runner.py` (lines 35-69)

```python
ENV_CONFIGS = {
    "linux-docker": {...},
    "linux-qemu": {...},
    "windows-qemu": {...},
    "android-qemu": {...},
    # NOTE: "macos-lume" is NOT in ENV_CONFIGS!
}
```

### Current Task Execution Flow

1. **CLI invocation**: `cb run task <path> --platform <type>`
2. **Platform validation** (line 259-262):
   ```python
   if not is_simulated and env_type not in ENV_CONFIGS:
       raise ValueError(f"Unknown env_type: {env_type}...")
   ```
   **Problem:** If env_type is `macos-lume`, this will fail!

3. **Environment container startup** (lines 298-310):
   - Gets config from `ENV_CONFIGS[env_type]`
   - Retrieves Docker image for QEMU platforms
   - Sets up volumes, ports, environment variables
   - Starts container via Docker

---

## CLI Arguments

### `--platform` Argument

**File:** `cua_bench/cli/main.py` (lines 112-117)

```python
parser.add_argument(
    "--platform",
    dest="platform",
    choices=["linux-docker", "linux-qemu", "windows-qemu", "android-qemu"],
    help="Platform type (auto-detected from task if not set)",
)
```

**Usage:**
```bash
# Currently supported platforms only
cb run task ./my_task --platform windows-qemu
cb run task ./my_task --platform linux-docker

# macos-lume is NOT in the choices
cb run task ./my_task --platform macos-lume  # ERROR: not a valid choice
```

### `--image` Argument

**File:** `cua_bench/cli/main.py` (lines 108-111)

```python
parser.add_argument(
    "--image",
    help="Image name to use (e.g., windows-qemu, windows-waa). See: cb image list",
)
```

**Usage:**
```bash
# Use a specific image (e.g., a Windows image with WinArena apps pre-installed)
cb run task ./my_task --image windows-waa

# For Lume VMs, this would be the VM name (e.g., created with `lume create`)
cb run task ./my_task --image my-macos-vm
```

### Image to env_type Derivation

From `_detect_env_type_and_image()`:

```python
if image_name and not env_type:
    if "windows" in image_name:
        env_type = "windows-qemu"
    elif "android" in image_name:
        env_type = "android-qemu"
    elif "linux-qemu" in image_name:
        env_type = "linux-qemu"
    else:
        env_type = "linux-docker"  # Default fallback
```

**Gap:** No detection for `macos` or `lume` in the image name!

---

## Image Management

### Platform Registration

**File:** `cua_bench/cli/commands/image.py` (lines 67-78 in platform.py)

```python
"macos-lume": {
    "image": None,
    "description": "macOS VM with Apple Virtualization (Lume, Apple Silicon only)",
    "internal_vnc_port": None,
    "internal_api_port": 5000,
    "requires_kvm": False,
    "image_marker": None,
    "os_type": "macos",
    "boot_timeout": 120,
    "use_overlays": False,
    "requires_apple_silicon": True,
}
```

### Image Creation

**File:** `cua_bench/cli/commands/image.py` (lines 765-789)

```python
def _create_macos_lume(args, config) -> int:
    """Create macos-lume image."""
    import platform as sys_platform

    if sys_platform.system() != "Darwin":
        print("Error: macOS image creation can only run on macOS hosts (Apple Silicon required).")
        return 1

    if not check_lume():
        print("Error: Lume is not installed.")
        print("\nInstall Lume:")
        print('  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/lume/scripts/install.sh)"')
        return 1

    name = getattr(args, "name", None) or "macos-lume"
    macos_version = getattr(args, "version", "sonoma")

    print("✓ Lume is installed")
    print(f"\nTo create a macOS VM ({macos_version}):")
    print(f"  lume create --name {name} --os {macos_version}")
    print("\nTo start:")
    print(f"  cb image shell {name}")
    return 0
```

### Checking Lume Installation

**File:** `cua_bench/cli/commands/platform.py` (lines 119-125)

```python
def check_lume() -> bool:
    """Check if Lume is installed."""
    try:
        result = subprocess.run(["lume", "--version"], capture_output=True, timeout=10)
        return result.returncode == 0
    except Exception:
        return False
```

### Platform Status Display

**File:** `cua_bench/cli/commands/platform.py` (lines 182-191)

```python
if name == "macos-lume":
    if not is_macos:
        status = "macOS only"
        status_color = "\033[90m"  # grey
    elif not lume_ok:
        status = "needs Lume"
        status_color = "\033[33m"  # yellow
    else:
        status = "ready"
        status_color = "\033[92m"  # green
```

### Commands

```bash
# List available platforms
cb platform list

# Get platform info
cb platform info macos-lume

# Create a new macOS Lume VM
cb image create macos-lume --name my-macos-vm --version sonoma

# Interactive shell into Lume VM
cb image shell my-macos-vm
```

---

## Configuration Files

### XDG Base Directory Standard

cua-bench follows XDG Base Directory Specification:

```
~/.local/share/cua-bench/       (XDG_DATA_HOME/cua-bench)
├── images/                      # Base VM images
│   ├── windows-qemu/            # Windows QEMU image files
│   ├── linux-qemu/              # Linux QEMU image files
│   └── my-macos-vm/             # Lume VM (native, not Docker)
└── overlays/                    # Task-specific overlays
    ├── task-1234-5678/
    └── task-9999-0000/

~/.local/state/cua-bench/        (XDG_STATE_HOME/cua-bench)
├── images.json                  # Image registry
└── runs/                         # Run history
```

### Image Registry

**File:** `~/.local/state/cua-bench/images.json`

```json
{
  "version": 1,
  "images": {
    "windows-qemu": {
      "platform": "windows-qemu",
      "path": "/Users/hanlynnke/.local/share/cua-bench/images/windows-qemu",
      "description": "Windows 11 VM",
      "created_at": "2026-04-03T20:00:00",
      "docker_image": "trycua/cua-qemu-windows:latest",
      "config": {"memory": "8G", "cpus": "8", "disk": "64G"},
      "tags": ["winarena"],
      "marker_file": "windows.boot"
    },
    "my-macos-vm": {
      "platform": "macos-lume",
      "path": "/Users/hanlynnke/.local/share/cua-bench/images/my-macos-vm",
      "description": "macOS Sonoma Lume VM",
      "created_at": "2026-04-03T21:00:00",
      "docker_image": null,
      "config": {},
      "tags": ["default"],
      "marker_file": null
    }
  }
}
```

### Configuration Directory

**Location:** `~/.cua/` (in project root or home directory)

**Files:**
- `config.yaml` - Agent and model defaults
- `agents.yaml` - Custom agent definitions

---

## Implementation Details

### Current Gaps for macOS Lume Support

1. **CLI --platform argument** doesn't include `macos-lume`
   - File: `cua_bench/cli/main.py:113-116`
   - Fix needed: Add `"macos-lume"` to choices

2. **ENV_CONFIGS** doesn't include `macos-lume` configuration
   - File: `cua_bench/runner/task_runner.py:36-69`
   - Fix needed: Add env_type config for `macos-lume`

3. **Environment type detection** doesn't recognize macOS os_type
   - File: `cua_bench/cli/commands/run.py:2184-2192`
   - Fix needed: Add `elif os_type and "macos" in os_type.lower()`

4. **Image name to env_type derivation** doesn't handle Lume VMs
   - File: `cua_bench/cli/commands/run.py:2142-2150`
   - Fix needed: Add detection for `"lume"` or `"macos"` in image name

### How Lume VMs Will Differ from QEMU Platforms

When properly implemented:

1. **No Docker container** - Lume VMs are native Apple VMs, not Docker containers
2. **No Docker image needed** - The "image" is actually a Lume VM name
3. **Different startup mechanism** - Uses `lume` CLI instead of `docker run`
4. **No overlay support needed** - Lume VMs can handle their own disk management
5. **Direct API connection** - Agent connects directly to VM's API port
6. **Native performance** - Full native macOS performance (no emulation)

### What Needs to be Implemented

To fully support running benchmarks with macOS Lume VMs:

1. **Update CLI argument parser**
   ```python
   choices=["linux-docker", "linux-qemu", "windows-qemu", "android-qemu", "macos-lume"]
   ```

2. **Add macos-lume to ENV_CONFIGS**
   ```python
   ENV_CONFIGS["macos-lume"] = {
       "image": None,
       "internal_vnc_port": None,
       "internal_api_port": 5000,
       "requires_kvm": False,
       "os_type": "macos",
       "use_overlays": False,
   }
   ```

3. **Update environment detection**
   ```python
   elif os_type and "macos" in os_type.lower():
       env_type = "macos-lume"
   ```

4. **Extend TaskRunner** to handle native Lume VMs
   - Detect when env_type is `macos-lume`
   - Use `lume start <vm-name>` instead of Docker
   - Wait for API port to become available
   - Connect agent directly (no Docker network needed)
   - Handle cleanup differently (no Docker containers to stop)

5. **Update image detection**
   ```python
   elif "lume" in image_name or "macos" in image_name:
       env_type = "macos-lume"
   ```

---

## Usage Example (Current State)

### What Currently Works

```bash
# List platforms (including macos-lume)
cb platform list

# Get macos-lume platform info
cb platform info macos-lume

# Create a new macOS Lume VM (manual process)
# This launches Lume creation tool
cb image create macos-lume --name my-vm

# Register an existing Lume VM
# (Would need manual registration if auto-discovery not working)
```

### What Doesn't Work Yet

```bash
# These will fail because macos-lume is not in CLI choices or ENV_CONFIGS:

# Run a task on macos-lume platform
cb run task ./my_task --platform macos-lume
# Error: argument --platform: invalid choice: 'macos-lume'

# Using image name
cb run task ./my_task --image my-macos-vm
# Error: Unknown env_type: linux-docker (defaults to this, then fails validation)
```

---

## References

### Key Files Mentioned

1. **Platform Configuration**: `cua_bench/cli/commands/platform.py`
   - Platform definitions and checks

2. **Image Management**: `cua_bench/cli/commands/image.py`
   - Image creation, registration, and shells

3. **Task Runner**: `cua_bench/runner/task_runner.py`
   - Core task execution logic

4. **CLI Main**: `cua_bench/cli/main.py`
   - Argument parser and command routing

5. **Run Command**: `cua_bench/cli/commands/run.py`
   - Execution logic for `cb run task` and `cb run dataset`

### Install Lume

```bash
/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/trycua/cua/main/libs/lume/scripts/install.sh)"
```

### Check Lume Status

```bash
# Verify Lume is installed
lume --version

# List Lume VMs
lume list

# Start a VM
lume start <vm-name>

# Stop a VM
lume stop <vm-name>
```

---

## Summary

**Status:** macOS Lume VMs are partially integrated into cua-bench:
- ✅ Platform definition exists in `PLATFORMS` dict
- ✅ Image creation/management commands partially implemented
- ✅ Lume installation check works
- ❌ CLI doesn't accept `--platform macos-lume`
- ❌ Task runner has no `macos-lume` configuration
- ❌ Environment detection doesn't recognize macOS
- ❌ Running benchmarks on Lume VMs not yet supported

**Next Steps:** Complete the implementation gaps listed in "What Needs to be Implemented" section above to enable full macOS Lume VM benchmark execution.
