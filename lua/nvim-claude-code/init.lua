-- nvim-claude-code: A Neovim plugin for integrating Claude Code CLI
-- Main module that handles context extraction, terminal interaction, and file editing

local M = {}

-- Default configuration for the plugin
-- Users can override these settings by calling setup() with different values
local config = {
	claude_code_binary = "claude", -- Path or command to run Claude Code CLI
}

local function is_valid_line_range(start_line, end_line, total_lines)
	return start_line > 0
		and end_line > 0
		and start_line <= total_lines
		and end_line <= total_lines
		and start_line <= end_line
end

local function get_visual_selection_range(lines)
	local start_pos = vim.fn.getpos("v")
	local end_pos = vim.fn.getpos(".")

	local start_line = math.min(start_pos[2], end_pos[2])
	local end_line = math.max(start_pos[2], end_pos[2])

	if is_valid_line_range(start_line, end_line, #lines) then
		return start_line, end_line
	end
	return nil, nil
end

local function get_mark_selection_range(lines)
	local mark_start = vim.api.nvim_buf_get_mark(0, "<")[1]
	local mark_end = vim.api.nvim_buf_get_mark(0, ">")[1]

	if is_valid_line_range(mark_start, mark_end, #lines) then
		return mark_start, mark_end
	end
	return nil, nil
end

local function get_selection_range(lines)
	local mode = vim.api.nvim_get_mode().mode

	if mode:match("^[vV\22]") then
		return get_visual_selection_range(lines)
	else
		return get_mark_selection_range(lines)
	end
end

-- Extract context from the current Neovim session
-- Returns a table containing all relevant information about the current file,
-- cursor position, selection, and project structure
local function get_current_context()
	-- Get basic buffer information
	local bufnr = vim.api.nvim_get_current_buf() -- Current buffer number
	local filename = vim.api.nvim_buf_get_name(bufnr) -- Full path to current file
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) -- All lines in buffer
	local content = table.concat(lines, "\n") -- Join lines into single string

	-- Get selection range if any
	local selection_start, selection_end = get_selection_range(lines)

	-- Get cursor position and check for text selection
	local cursor_line = vim.fn.line(".") -- Current cursor line number

	-- Attempt to find the project root directory
	-- Look for common project indicators moving up the directory tree
	local project_root = nil
	if filename and filename ~= "" then
		-- Search for project markers (git repo, package files, etc.)
		local found = vim.fs.find({ ".git", "package.json", "Cargo.toml", "pyproject.toml", "go.mod" }, {
			path = filename, -- Start from current file's directory
			upward = true, -- Search upward through parent directories
		})
		if found and #found > 0 then
			project_root = vim.fs.dirname(found[1]) -- Get directory containing project marker
		end
	end

	-- Return all context information in a structured table
	return {
		filename = filename, -- Full path to current file
		content = content, -- Complete file content as string
		lines = lines, -- Array of individual lines
		cursor_line = cursor_line, -- Current cursor position
		selection_start = selection_start, -- Start of text selection (if any)
		selection_end = selection_end, -- End of text selection (if any)
		project_root = project_root, -- Root directory of project (if detected)
	}
end

-- Monitor Claude Code output for file replacement requests
-- This function checks if Claude Code wants to update the current file
-- by looking for difference between buffer and temp file
local function check_for_file_replacement(output_lines, context, temp_file)
	if vim.fn.filereadable(temp_file) == 1 then
		local temp_content = vim.fn.readfile(temp_file) -- Read new content from temp file
		local temp_content_str = table.concat(temp_content, "\n") -- Convert to string for comparison
		if context.filename and context.filename ~= "" then
			if context.content ~= temp_content_str then
				-- Claude Code has written new content to the temp file, apply it to the buffer
				-- Find the original buffer and replace its contents
				local original_buf = vim.fn.bufnr(context.filename)
				if original_buf ~= -1 then
					-- Replace entire buffer content with new content
					vim.api.nvim_buf_set_lines(original_buf, 0, -1, false, temp_content)
					-- Send confirmation message to terminal
					vim.notify("File contents updated from Claude", vim.log.levels.INFO)
				end
			end
		end
	end
end

-- Runs a command in the background and captures its output.
-- The `on_finish` parameter is an optional callback function to run
-- once the command is complete, receiving the output as an argument.
local function run_terminal_command(cmd, callback, opts)
	opts = opts or {}
	local height = opts.height or 15

	-- Store output lines
	local output_lines = {}

	-- Create vertical split
	vim.cmd("split")

	-- Create a new scratch buffer
	local buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_set_current_buf(buf)

	-- Set buffer options
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].swapfile = false
	vim.bo[buf].filetype = "terminal"

	-- Resize to specified height
	vim.cmd("resize " .. height)

	-- Function to handle job exit
	local function on_exit(job_id, exit_code, event_type)
		-- Schedule the callback and buffer cleanup to run in the main thread
		vim.schedule(function()
			-- Close the buffer/window
			local win = vim.fn.bufwinid(buf)
			if win ~= -1 then
				vim.api.nvim_win_close(win, true)
			end

			-- Call the callback with the collected output
			if callback then
				callback(output_lines, exit_code)
			end
		end)
	end

	-- Function to handle stdout
	local function on_stdout(job_id, data, event_type)
		-- data is a list of lines
		if data then
			-- Limit output buffer size to prevent memory issues
			for _, line in ipairs(data) do
				-- Skip empty lines at the end
				if line ~= "" then
					-- Prevent excessive memory usage by limiting output buffer
					if #output_lines < 10000 then
						table.insert(output_lines, line)
					else
						-- Remove oldest lines if buffer gets too large
						table.remove(output_lines, 1)
						table.insert(output_lines, line)
					end
				end
			end
		end
	end

	-- Start the terminal job
	local job_id = vim.fn.termopen(cmd, {
		on_exit = on_exit,
		on_stdout = on_stdout,
		stdout_buffered = true, -- Buffer stdout to get complete lines
	})

	-- Enter insert mode to interact with the terminal
	vim.cmd("startinsert")

	-- Return the job ID in case the caller wants to manipulate it
	return job_id, buf
end

-- Main function that orchestrates the Claude Code integration
-- Creates temporary files, builds context, and runs Claude Code in terminal
local function run_claude_code(user_input, context)
	-- Create temporary files for communication with Claude Code
	local context_file = vim.fn.tempname() -- File to pass context to Claude
	local temp_buffer_file = vim.fn.tempname() -- File for Claude to write changes to

	-- Initialize the output file with current content so Claude can read it first
	-- This allows Claude to see the current state before making changes
	if context.filename and context.filename ~= "" then
		local file = io.open(temp_buffer_file, "w")
		if file then
			local success, err = pcall(function()
				file:write(context.content) -- Write current buffer content to temp file
			end)
			file:close()
			if not success then
				vim.notify("Failed to write to output file: " .. tostring(err), vim.log.levels.ERROR)
				return
			end
		else
			vim.notify("Failed to create output file", vim.log.levels.ERROR)
			return
		end
	end

	-- Build instructions for Claude Code explaining the integration protocol
	-- This tells Claude how to interact with the editor through temporary files
	local context_info = string.format(
		[[
      You are processing a file that's open in an editor. You will receive the filename and project root, and either the current cursor line
      or selected lines, as well as a prompt. Process and execute the prompt as given. You can also do other things as necessary within the
      given project.

      IMPORTANT: If you need to modify the currently open file, do NOT write to disk directly. Instead:
      1. Read the current file contents from the temporary buffer file: %s
      2. Write your complete updated file contents to the temporary buffer file: %s  
      Always read the temporary buffer file first before writing. Never attempt to write the output buffer before reading.
      The editor will detect this change and replace the editor contents with the temporary file.
    ]],
		temp_buffer_file,
		temp_buffer_file
	)

	-- Add current file information to context
	-- Show relative path if we detected a project root, otherwise show full path
	if context.filename and context.filename ~= "" then
		local display_filename = context.filename
		-- Convert to relative path if within project
		if context.project_root and context.filename:sub(1, #context.project_root) == context.project_root then
			display_filename = context.filename:sub(#context.project_root + 2) -- Remove project root + slash
		end
		context_info = context_info .. "Current file: " .. display_filename .. "\n"
	end

	-- Add project root information if detected
	if context.project_root then
		context_info = context_info .. "Project root: " .. context.project_root .. "\n\n"
	else
		context_info = context_info .. "\n" -- No project root found
	end

	-- Add focused context: either selected text or current cursor line
	if context.selection_start and context.selection_end then
		-- User has text selected - include the selected lines
		context_info = context_info
			.. string.format("Selected lines %d-%d:\n", context.selection_start, context.selection_end)
		local selected_lines = {}
		-- Extract the selected lines from the buffer
		for i = context.selection_start, context.selection_end do
			if i >= 1 and i <= #context.lines then
				table.insert(selected_lines, context.lines[i])
			else
				table.insert(selected_lines, "") -- Handle edge cases with empty lines
			end
		end
		context_info = context_info .. table.concat(selected_lines, "\n") .. "\n\n"
	else
		-- No selection - show just the current cursor line
		context_info = context_info .. string.format("Current line %d:\n", context.cursor_line)
		local current_line = ""
		if context.cursor_line >= 1 and context.cursor_line <= #context.lines then
			current_line = context.lines[context.cursor_line]
		end
		context_info = context_info .. current_line .. "\n\n"
	end

	-- Include the complete file content for Claude's reference
	context_info = context_info .. "Full file content (from editor buffer):\n" .. context.content

	-- Write all context information to temporary file for Claude Code
	local file = io.open(context_file, "w")
	if file then
		local success, err = pcall(function()
			file:write(context_info) -- Write complete context to temp file
		end)
		file:close()
		if not success then
			vim.notify("Failed to write context file: " .. tostring(err), vim.log.levels.ERROR)
			return
		end
	else
		vim.notify("Failed to create temporary file", vim.log.levels.ERROR)
		return
	end

	-- Build command to run Claude Code with context and user prompt
	-- Change to project root before running Claude Code if project root is defined
	local cmd = ""
	if context.project_root then
		cmd = "cd " .. vim.fn.shellescape(context.project_root) .. " && "
	end
	cmd = cmd
		.. "cat "
		.. vim.fn.shellescape(context_file)
		.. " | "
		.. config.claude_code_binary
		.. " "
		.. vim.fn.shellescape(user_input)

	-- Create terminal window for Claude Code output
	run_terminal_command(cmd, function(output, exit_code)
		check_for_file_replacement(output, context, temp_buffer_file)
		-- Clean up temp files
		os.remove(context_file)
		os.remove(temp_buffer_file)
	end)
end

-- Main entry point called when user presses <leader>CC
-- Collects context and prompts user for input
function M.run()
	-- Extract current editor context (file, cursor, selection, etc.)
	local context = get_current_context()

	-- Prompt user for input using Neovim's built-in input UI
	vim.ui.input({
		prompt = "Claude Code Input: ", -- Prompt text shown to user
		default = "", -- Empty default input
	}, function(input)
		-- Only proceed if user entered something
		if input and input ~= "" then
			run_claude_code(input, context) -- Start Claude Code integration
		end
	end)
end

-- Setup function called by users to configure the plugin
-- Allows customization of the Claude Code binary path and other settings
function M.setup(opts)
	-- Merge user configuration with defaults
	-- vim.tbl_deep_extend merges nested tables properly
	config = vim.tbl_deep_extend("force", config, opts or {})
end

-- Export the module table so other files can require() this module
return M
