local M = {}

local config = {
    claude_code_binary = 'claude'
}

local function get_current_context()
    local bufnr = vim.api.nvim_get_current_buf()
    local filename = vim.api.nvim_buf_get_name(bufnr)
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local content = table.concat(lines, '\n')
    
    local cursor_line = vim.fn.line('.')
    local selection_start, selection_end = nil, nil
    
    local mode = vim.fn.mode()
    if mode == 'v' or mode == 'V' or mode == '\22' then
        selection_start = vim.fn.line("'<")
        selection_end = vim.fn.line("'>")
    end
    
    return {
        filename = filename,
        content = content,
        lines = lines,
        cursor_line = cursor_line,
        selection_start = selection_start,
        selection_end = selection_end
    }
end

local function create_output_window()
    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_option(buf, 'buftype', 'nofile')
    vim.api.nvim_buf_set_option(buf, 'swapfile', false)
    vim.api.nvim_buf_set_option(buf, 'filetype', 'markdown')
    
    local width = math.floor(vim.o.columns * 0.8)
    local height = math.floor(vim.o.lines * 0.8)
    local row = math.floor((vim.o.lines - height) / 2)
    local col = math.floor((vim.o.columns - width) / 2)
    
    local opts = {
        relative = 'editor',
        width = width,
        height = height,
        row = row,
        col = col,
        style = 'minimal',
        border = 'rounded',
        title = ' Claude Code Output ',
        title_pos = 'center'
    }
    
    local win = vim.api.nvim_open_win(buf, true, opts)
    
    vim.api.nvim_buf_set_keymap(buf, 'n', 'q', ':q<CR>', {noremap = true, silent = true})
    vim.api.nvim_buf_set_keymap(buf, 'n', '<Esc>', ':q<CR>', {noremap = true, silent = true})
    
    return buf, win
end

local function run_claude_code(user_input, context)
    local temp_file = vim.fn.tempname()
    local context_info = ""
    
    if context.filename and context.filename ~= "" then
        context_info = context_info .. "Current file: " .. context.filename .. "\n\n"
    end
    
    if context.selection_start and context.selection_end then
        context_info = context_info .. string.format("Selected lines %d-%d:\n", context.selection_start, context.selection_end)
        local selected_lines = {}
        for i = context.selection_start, context.selection_end do
            table.insert(selected_lines, context.lines[i] or "")
        end
        context_info = context_info .. table.concat(selected_lines, '\n') .. "\n\n"
    else
        context_info = context_info .. string.format("Current line %d:\n", context.cursor_line)
        local current_line = context.lines[context.cursor_line] or ""
        context_info = context_info .. current_line .. "\n\n"
    end
    
    context_info = context_info .. "Full file content (from editor buffer):\n" .. context.content
    
    local file = io.open(temp_file, 'w')
    if file then
        file:write(context_info)
        file:close()
    else
        vim.notify("Failed to create temporary file", vim.log.levels.ERROR)
        return
    end
    
    local escaped_input = user_input:gsub('"', '\\"')
    local cmd = string.format('cat "%s" | %s -p "%s"', temp_file, config.claude_code_binary, escaped_input)
    
    local output_buf, output_win = create_output_window()
    
    vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, {"Running Claude Code...", ""})
    
    local output_lines = {}
    
    vim.fn.jobstart(cmd, {
        stdout_buffered = false,
        stderr_buffered = false,
        on_stdout = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        table.insert(output_lines, line)
                    end
                end
                vim.schedule(function()
                    vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, output_lines)
                end)
            end
        end,
        on_stderr = function(_, data)
            if data then
                for _, line in ipairs(data) do
                    if line ~= "" then
                        table.insert(output_lines, "ERROR: " .. line)
                    end
                end
                vim.schedule(function()
                    vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, output_lines)
                end)
            end
        end,
        on_exit = function(_, code)
            vim.schedule(function()
                if code ~= 0 then
                    table.insert(output_lines, "")
                    table.insert(output_lines, string.format("Process exited with code: %d", code))
                    vim.api.nvim_buf_set_lines(output_buf, 0, -1, false, output_lines)
                end
            end)
            os.remove(temp_file)
        end
    })
end

function M.run()
    local context = get_current_context()
    
    vim.ui.input({
        prompt = 'Claude Code Input: ',
        default = '',
    }, function(input)
        if input and input ~= '' then
            run_claude_code(input, context)
        end
    end)
end

function M.setup(opts)
    config = vim.tbl_deep_extend('force', config, opts or {})
end

return M