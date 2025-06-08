# nvim-claude-code

A Neovim plugin that integrates [Claude Code](https://claude.ai/code) directly into your editor workflow.

## Features

- **Context-aware prompts**: Automatically includes current file content and cursor/selection context
- **Floating output window**: View Claude Code responses in a clean, dismissible panel  
- **Simple keymap**: Trigger with `<leader>CC` from normal mode
- **Configurable**: Customize the Claude Code binary path

## Requirements

- Neovim 0.7+
- [Claude Code CLI](https://docs.anthropic.com/en/docs/claude-code/cli-usage) installed and accessible

## Installation

### Using lazy.nvim

```lua
{
  dir = "pvnick/nvim-claude-code",
  name = "nvim-claude-code",
  config = function()
    require("nvim-claude-code").setup({
      claude_code_binary = "claude" -- default
    })
    
    vim.keymap.set('n', '<leader>CC', function()
      require('nvim-claude-code').run()
    end, { desc = 'Run Claude Code' })
  end
}
```

### Using packer.nvim

```lua
use {
  "pvnick/nvim-claude-code",
  config = function()
    require("nvim-claude-code").setup()
    vim.keymap.set('n', '<leader>CC', require('nvim-claude-code').run, { desc = 'Run Claude Code' })
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
   
   vim.keymap.set('n', '<leader>CC', function()
     require('nvim-claude-code').run()
   end, { desc = 'Run Claude Code' })
   ```

## Usage

1. **Open a file** in Neovim
2. **Position your cursor** on the line you want context from, or **select text** for multi-line context
3. **Press `<leader>CC`** to open the input prompt
4. **Enter your prompt** and press Enter
5. **View the response** in the floating window that appears
6. **Close the window** by pressing `q` or `Esc`

### What gets sent to Claude Code

The plugin automatically includes:
- Your input prompt
- Current file path and full content
- Current cursor line OR selected text range
- Context about which lines are focused

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
| Normal | `<leader>CC` | Open Claude Code input prompt |
| Output Window | `q` | Close output window |
| Output Window | `<Esc>` | Close output window |

## License

MIT License - see [LICENSE](LICENSE) file for details.
