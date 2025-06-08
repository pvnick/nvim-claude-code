# nvim-claude-code

A Neovim plugin that integrates [Claude Code](https://claude.ai/code) directly into your editor workflow.

## Features

- **Context-aware prompts**: Automatically includes current file content and cursor/selection context
- **Interactive terminal output**: View Claude Code responses in a dedicated terminal window
- **In-place file editing**: Claude Code can directly modify your open buffer without saving to disk
- **Project-aware**: Automatically detects project root and provides relative file paths
- **Smart context extraction**: Sends either current cursor line or selected text range
- **Simple keymap**: Trigger with `<leader>CC` from normal mode
- **Configurable**: Customize the Claude Code binary path

## Requirements

- Neovim 0.7+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/cli-usage) installed and accessible

## Installation

### Using lazy.nvim

```lua
return {
  {
    "pvnick/nvim-claude-code",
    name = "nvim-claude-code",
    config = function()
      require("nvim-claude-code").setup({
        claude_code_binary = "claude", -- default
      })

      vim.keymap.set({"n", "x"}, "<leader>CC", function()
        require("nvim-claude-code").run()
      end, { desc = "Run Claude Code" })
    end,
  },
}
```

### Using packer.nvim

```lua
use {
  "pvnick/nvim-claude-code",
  config = function()
    require("nvim-claude-code").setup()
    vim.keymap.set({'n', 'x'}, '<leader>CC', require('nvim-claude-code').run, { desc = 'Run Claude Code' })
  end
}
```

### Manual Installation

1. **Copy the plugin files:**
   ```bash
   mkdir -p ~/.config/nvim/lua
   cp -r /path/to/nvim-claude-code/lua/nvim-claude-code ~/.config/nvim/lua/
   ```

2. **Add to your `init.lua`:**
   ```lua
   require("nvim-claude-code").setup()
   
   vim.keymap.set({'n', 'x'}, '<leader>CC', function()
     require('nvim-claude-code').run()
   end, { desc = 'Run Claude Code' })
   ```

## Usage

1. **Open a file** in Neovim
2. **Position your cursor** on the line you want context from, or **select text** for multi-line context
3. **Press `<leader>CC`** (works in normal or visual mode) to open the input prompt
4. **Enter your prompt** and press Enter
5. **View the response** in the interactive terminal window that opens
6. **If Claude Code modifies your file**, the changes will automatically appear in your buffer

### What gets sent to Claude Code

The plugin automatically includes:
- Your input prompt
- Current file path (relative to project root when detected)
- Full file content from the editor buffer
- Current cursor line OR selected text range with line numbers
- Project root directory (auto-detected from .git, package.json, Cargo.toml, etc.)

### In-place File Editing

Claude Code can directly modify your open file through the plugin's special interface:
- Changes appear immediately in your buffer without saving to disk
- No need to manually copy/paste code from Claude's response
- Preserves your undo history and editor state

## Configuration

```lua
require("nvim-claude-code").setup({
  claude_code_binary = "claude" -- Path to Claude Code CLI binary
})
```

### Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `claude_code_binary` | string | `"claude"` | Path or command to run Claude Code CLI |

## Key Mappings

| Mode | Key | Action |
|------|-----|--------|
| Normal/Visual | `<leader>CC` | Open Claude Code input prompt |
| Terminal Window | `:q` | Close terminal window |

## How It Works

The plugin creates a seamless integration between Neovim and Claude Code:

1. **Context Collection**: Gathers current file state, cursor position, and project information
2. **Temporary Files**: Creates temporary files for secure communication with Claude Code
3. **Terminal Integration**: Opens an interactive terminal to show Claude's real-time output
4. **Smart File Updates**: Uses a token-based system to detect when Claude wants to modify your file
5. **Buffer Management**: Updates your editor buffer directly without touching the file system

## Supported Project Types

The plugin automatically detects project roots by looking for:
- `.git` directories
- `package.json` (Node.js)
- `Cargo.toml` (Rust)
- `pyproject.toml` (Python)
- `go.mod` (Go)

## License

MIT License - see [LICENSE](LICENSE) file for details.
