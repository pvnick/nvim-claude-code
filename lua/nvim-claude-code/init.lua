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
		and start_line ~= end_line
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
-- by looking for a special token in the output
local function check_for_file_replacement(
	output_lines,
	context,
	term_buf,
	temp_file,
	replacement_token,
	cleanup_callback
)
	-- Scan through all output lines looking for the replacement token
	for _, line in ipairs(output_lines) do
		if line:find(replacement_token, 1, true) then -- Found the replacement signal
			-- Claude Code has written new content to the temp file, apply it to the buffer
			if vim.fn.filereadable(temp_file) == 1 then
				local temp_content = vim.fn.readfile(temp_file) -- Read new content from temp file
				if context.filename and context.filename ~= "" then
					-- Find the original buffer and replace its contents
					local original_buf = vim.fn.bufnr(context.filename)
					if original_buf ~= -1 then
						-- Replace entire buffer content with new content
						vim.api.nvim_buf_set_lines(original_buf, 0, -1, false, temp_content)
						-- Send confirmation message to terminal
						local success = pcall(
							vim.fn.chansend,
							vim.b[term_buf].terminal_job_id,
							"\r\n✓ File contents replaced in editor buffer\r\n"
						)
						if not success then
							vim.notify("File replaced but could not send terminal message", vim.log.levels.WARN)
						end
					end
				end
			end
			-- Clean up temporary files after successful replacement
			if cleanup_callback then
				cleanup_callback()
			end
			return -- Exit early since we found and processed the token
		end
	end
	-- If no replacement token found in any output line, still clean up
	if cleanup_callback then
		cleanup_callback()
	end
end

-- Create a new terminal window for displaying Claude Code output
-- Opens a horizontal split and sets up a terminal buffer
local function create_terminal()
	-- Create horizontal split window for terminal output
	vim.cmd("split") -- Split window horizontally
	vim.cmd("resize 15") -- Set terminal window height to 15 lines

	-- Create a new buffer for the terminal
	local term_buf = vim.api.nvim_create_buf(false, true) -- unlisted, scratch buffer
	vim.api.nvim_win_set_buf(0, term_buf) -- Set current window to use terminal buffer

	return term_buf
end

-- Main function that orchestrates the Claude Code integration
-- Creates temporary files, builds context, and runs Claude Code in terminal
local function run_claude_code(user_input, context)
	-- Create temporary files for communication with Claude Code
	local context_file = vim.fn.tempname() -- File to pass context to Claude
	local output_file = vim.fn.tempname() -- File for Claude to write changes to
	-- Generate unique number that Claude will combine with NVIM_REPLACE_ prefix
	local replacement_number = math.random(100000, 999999)
	local replacement_token = "NVIM_REPLACE_" .. replacement_number

	-- Initialize the output file with current content so Claude can read it first
	-- This allows Claude to see the current state before making changes
	if context.filename and context.filename ~= "" then
		local file = io.open(output_file, "w")
		if file then
			file:write(context.content) -- Write current buffer content to temp file
			file:close()
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
  1. Read the current file contents from: %s
  2. Write your complete updated file contents to: %s  
  3. Output a token by concatenating "NVIM_REPLACE_" with "%s"
  The editor will detect this token and replace the buffer contents with the temporary file.
  ]],
		output_file,
		output_file,
		replacement_number
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
		file:write(context_info) -- Write complete context to temp file
		file:close()
	else
		vim.notify("Failed to create temporary file", vim.log.levels.ERROR)
		return
	end

	-- Build command to run Claude Code with context and user prompt
	local escaped_input = user_input:gsub('"', '\\"') -- Escape quotes in user input
	-- Change to project root before running Claude Code if project root is defined
	local cd_prefix = ""
	if context.project_root then
		cd_prefix = string.format('cd "%s" && ', context.project_root)
	end
	-- Pipe context file to Claude Code with user's prompt as argument
	local cmd = string.format('%scat "%s" | %s "%s"', cd_prefix, context_file, config.claude_code_binary, escaped_input)

	-- Create terminal window for Claude Code output
	local term_buf = create_terminal()

	-- Track output lines to detect file replacement requests
	local output_lines = {}

	-- Start Claude Code process with callback handlers
	local job_id = vim.fn.jobstart(cmd, {
		-- Capture standard output and store for file replacement detection
		on_stdout = function(_, data)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						table.insert(output_lines, line) -- Store each output line
					end
				end
			end
		end,
		-- Capture error output and mark it clearly
		on_stderr = function(_, data)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						table.insert(output_lines, "ERROR: " .. line) -- Prefix errors
					end
				end
			end
		end,
		-- Handle process completion
		on_exit = function(_, code)
			vim.schedule(function() -- Schedule for main thread execution
				-- Function to clean up temporary files
				local cleanup = function()
					os.remove(context_file) -- Delete context temp file
					os.remove(output_file) -- Delete output temp file
				end

				-- Only check for file replacement if Claude Code succeeded
				if code == 0 then
					check_for_file_replacement(output_lines, context, term_buf, output_file, replacement_token, cleanup)
				else
					cleanup() -- Clean up immediately on error
				end
			end)
		end,
		-- Connect job output to terminal buffer
		pty = true,
		stdout_buffered = false,
		stderr_buffered = false,
	})

	-- Store job id in terminal buffer for later communication
	vim.b[term_buf].terminal_job_id = job_id

	-- Enter insert mode in the terminal so user can see live output
	vim.cmd("startinsert")
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
