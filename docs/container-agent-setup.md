# Container Agent Setup

## How AI Agents Work in Container Mode

When you run Sprinty with `--container`, the agent CLI tools (opencode and cursor-agent) need to be available inside the isolated container environment.

---

## What Gets Installed/Mounted?

### OpenCode (Default)

**Automatically installed in container** ✅

When the container starts, OpenCode is:
1. **First**: Checked if mounted from host at `/host-bin/opencode`
2. **If not found**: Automatically installed inside the container using:
   ```bash
   curl -fsSL https://opencode.ai/install | bash
   ```

**Result**: OpenCode works out of the box in container mode! 🎉

### Cursor Agent

**Mounted from host** (not installed)

When the container starts, cursor-agent is:
1. **Searched** on the host system in common locations
2. **Mounted** into the container at `/opt/cursor-agent` and `/host-bin`
3. **Symlinked** to `/usr/local/bin/cursor-agent`

**Requirement**: You must have cursor-agent installed on the HOST machine.

---

## Setup for Each Agent

### OpenCode (Recommended for Beginners)

#### No setup required! ✅

OpenCode works automatically in container mode:

```bash
# Just run sprinty (opencode is default)
sprinty init my-project --prd requirements.md
sprinty --container --workspace . --monitor run
```

The first container startup will install opencode automatically (takes ~30 seconds).

#### Optional: Pre-install on Host

To speed up first container startup, install on host:

```bash
# Install opencode on host
curl -fsSL https://opencode.ai/install | bash
source ~/.bashrc

# Now it will be mounted instead of installed
sprinty --container --workspace . run
```

---

### Cursor Agent (Requires Setup)

#### Step 1: Install on Host

```bash
curl https://cursor.com/install -fsS | bash
```

#### Step 2: Verify Installation

```bash
cursor-agent --version
# Output: 2026.01.02-80e4d9b (or similar)
```

#### Step 3: Update Config to Use Cursor Agent

Edit `.sprinty/config.json`:

```json
{
  "agent": {
    "cli_tool": "cursor-agent",
    "model": "opus-4.5-thinking"
  }
}
```

#### Step 4: Run in Container

```bash
sprinty --container --workspace . --monitor run
```

The container will automatically mount cursor-agent from your host installation.

---

## How It Works (Technical Details)

### Container Startup Sequence

1. **Container is launched** with Apptainer/Singularity
2. **Setup script runs** (`/tmp/setup.sh`)
3. **For OpenCode:**
   - Check if mounted from host at `/host-bin/opencode`
   - If not found, run install script
   - Symlink to `/usr/local/bin/opencode`
4. **For Cursor Agent:**
   - Check for mount at `/opt/cursor-agent`
   - Find binary and symlink to `/usr/local/bin/cursor-agent`
   - Mount auth credentials from `~/.config/cursor/`
5. **Verify both agents** and report availability

### Host Mount Points

The container mounts these directories from your host:

| Host Path | Container Path | Purpose |
|-----------|----------------|---------|
| `$workspace` | `/workspace` | Your project files |
| `~/.local/bin/` | `/host-bin` | Binary executables (opencode, cursor-agent) |
| `/opt/cursor-agent/` | `/opt/cursor-agent` | Cursor agent installation |
| `~/.config/cursor/` | `/root/.config/cursor/` | Cursor authentication |
| `~/.gitconfig` | `/root/.gitconfig` | Git configuration |

---

## Verification

### Check What's Available in Container

After container starts, you'll see:

```
Agent CLI availability:
  ✓ opencode: /usr/local/bin/opencode
  ✓ cursor-agent: /usr/local/bin/cursor-agent
```

Or if something is missing:

```
Agent CLI availability:
  ✓ opencode: /usr/local/bin/opencode
  ✗ cursor-agent: not found
    (Install on host: curl https://cursor.com/install -fsS | bash)
```

### Manual Verification Inside Container

If you want to manually check inside the container:

```bash
# Launch interactive shell in container
sprinty --container --workspace . exec bash

# Inside container:
which opencode
which cursor-agent
opencode --version
cursor-agent --version
```

---

## Troubleshooting

### OpenCode Not Available

**Symptom**: `⚠ opencode installation may have failed`

**Solutions**:

1. **Pre-install on host** (recommended):
   ```bash
   curl -fsSL https://opencode.ai/install | bash
   source ~/.bashrc
   ```

2. **Check install script** manually:
   ```bash
   # Test the install script
   curl -fsSL https://opencode.ai/install | bash
   ```

3. **Clear container cache** and rebuild:
   ```bash
   sprinty container clear
   sprinty --container --workspace . run
   ```

### Cursor Agent Not Available

**Symptom**: `✗ cursor-agent: not found`

**Solutions**:

1. **Install on host**:
   ```bash
   curl https://cursor.com/install -fsS | bash
   ```

2. **Verify installation**:
   ```bash
   which cursor-agent
   cursor-agent --version
   ```

3. **Check mount locations**:
   ```bash
   ls -la ~/.local/bin/cursor-agent
   ls -la /usr/local/bin/cursor-agent
   ```

4. **If installed but not found**, try reinstalling:
   ```bash
   # Reinstall cursor-agent
   curl https://cursor.com/install -fsS | bash
   ```

### Authentication Issues

**Cursor Agent Authentication**:

If cursor-agent is found but authentication fails:

```bash
# On host, login
cursor-agent auth login

# Verify auth file exists
ls -la ~/.config/cursor/auth.json
```

This auth file will be automatically mounted in the container.

**OpenCode Authentication**:

OpenCode's free model doesn't require authentication. For paid models:

```bash
# Set API key
export OPENCODE_API_KEY="your-key"

# Run container with environment variable
OPENCODE_API_KEY="your-key" sprinty --container --workspace . run
```

---

## Performance Notes

### First Run vs. Subsequent Runs

**First Container Run** (OpenCode auto-install):
- Takes ~30-60 seconds to install opencode
- Installs system packages if needed
- Subsequent runs are fast (opencode is mounted)

**First Container Run** (Cursor Agent mount):
- Nearly instant (just mounts from host)
- No installation needed

**Cached Container**:
- First run: 2-3 minutes (builds cache with packages)
- Subsequent runs: <2 seconds (uses cache)

### Optimizing Performance

1. **Pre-install on host**:
   ```bash
   curl -fsSL https://opencode.ai/install | bash
   curl https://cursor.com/install -fsS | bash
   ```

2. **Pre-build container cache**:
   ```bash
   sprinty container build
   ```

3. **Result**: Container starts in <2 seconds with both agents ready!

---

## Best Practices

### For OpenCode Users (Default)

✅ **Recommended**: Just use it! Auto-installation works great.

🚀 **Optimal**: Pre-install on host for faster startup:
```bash
curl -fsSL https://opencode.ai/install | bash
```

### For Cursor Agent Users

✅ **Required**: Install on host first:
```bash
curl https://cursor.com/install -fsS | bash
```

✅ **Recommended**: Configure once in `.sprinty/config.json`

### For Both

✅ **Pre-build cache** for instant startup:
```bash
sprinty container build
```

✅ **Verify before long runs**:
```bash
sprinty --container --workspace . exec bash
# Check: which opencode && which cursor-agent
```

---

## Summary

| Agent | Container Behavior | Setup Required | First Run Time |
|-------|-------------------|----------------|----------------|
| **OpenCode** | Auto-installs | ❌ None | ~30-60 seconds |
| **Cursor Agent** | Mounted from host | ✅ Install on host | <2 seconds |

**Bottom line**: OpenCode works out of the box, cursor-agent requires host installation.

---

## See Also

- [Switching Between Agents](switching-agents.md)
- [Container Mode Guide](../README.md#-container-mode)
- [OpenCode Quick Start](opencode-quickstart.md)
