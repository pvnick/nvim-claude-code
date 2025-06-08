local M = {}

local config = {
	claude_code_binary = "claude",
}

local function get_current_context()
	local bufnr = vim.api.nvim_get_current_buf()
	local filename = vim.api.nvim_buf_get_name(bufnr)
	local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
	local content = table.concat(lines, "\n")

	local cursor_line = vim.fn.line(".")
	local selection_start, selection_end = nil, nil

	local mode = vim.fn.mode()
	if mode == "v" or mode == "V" or mode == "\22" then
		selection_start = vim.fn.line("'<")
		selection_end = vim.fn.line("'>")
	end

	local project_root = nil
	if filename and filename ~= "" then
		local found = vim.fs.find({'.git', 'package.json', 'Cargo.toml', 'pyproject.toml', 'go.mod'}, {
			path = filename,
			upward = true
		})
		if found and #found > 0 then
			project_root = vim.fs.dirname(found[1])
		end
	end

	return {
		filename = filename,
		content = content,
		lines = lines,
		cursor_line = cursor_line,
		selection_start = selection_start,
		selection_end = selection_end,
		project_root = project_root,
	}
end

local function check_for_file_replacement(output_lines, context, term_buf, temp_file, replacement_token, cleanup_callback)
	for _, line in ipairs(output_lines) do
		if line:find(replacement_token, 1, true) then
			if vim.fn.filereadable(temp_file) == 1 then
				local temp_content = vim.fn.readfile(temp_file)
				if context.filename and context.filename ~= "" then
					local original_buf = vim.fn.bufnr(context.filename)
					if original_buf ~= -1 then
						vim.api.nvim_buf_set_lines(original_buf, 0, -1, false, temp_content)
						local success = pcall(vim.fn.chansend, vim.b[term_buf].terminal_job_id, "\r\n✓ File contents replaced in editor buffer\r\n")
						if not success then
							vim.notify("File replaced but could not send terminal message", vim.log.levels.WARN)
						end
					end
				end
			end
			if cleanup_callback then cleanup_callback() end
			return
		end
	end
	-- If no replacement token found, still do cleanup
	if cleanup_callback then cleanup_callback() end
end

local function create_terminal()
	vim.cmd('split')
	vim.cmd('resize 15')
	
	local term_buf = vim.api.nvim_create_buf(false, true)
	vim.api.nvim_win_set_buf(0, term_buf)
	
	return term_buf
end

local function run_claude_code(user_input, context)
	local context_file = vim.fn.tempname()
	local output_file = vim.fn.tempname()
	local replacement_token = "NVIM_REPLACE_" .. math.random(100000, 999999)
	
	-- Create the output file with current content so Claude can read it first
	if context.filename and context.filename ~= "" then
		local file = io.open(output_file, "w")
		if file then
			file:write(context.content)
			file:close()
		else
			vim.notify("Failed to create output file", vim.log.levels.ERROR)
			return
		end
	end
	
	local context_info = string.format([[
  You are processing a file that's open in an editor. You will receive the filename and project root, and either the current cursor line
  or selected lines, as well as a prompt. Process and execute the prompt as given. You can also do other things as necessary within the
  given project.
  
  IMPORTANT: If you need to modify the currently open file, do NOT write to disk directly. Instead:
  1. Use the Read tool to read this temporary file first: %s
  2. Write the complete new file contents to the same temporary file: %s
  3. After writing to the temporary file, output this exact token: %s
  The editor will detect this token and replace the buffer contents with the temporary file.
  ]], output_file, output_file, replacement_token)

	if context.filename and context.filename ~= "" then
		local display_filename = context.filename
		if context.project_root and context.filename:sub(1, #context.project_root) == context.project_root then
			display_filename = context.filename:sub(#context.project_root + 2)
		end
		context_info = context_info .. "Current file: " .. display_filename .. "\n"
	end

	if context.project_root then
		context_info = context_info .. "Project root: " .. context.project_root .. "\n\n"
	else
		context_info = context_info .. "\n"
	end

	if context.selection_start and context.selection_end then
		context_info = context_info
			.. string.format("Selected lines %d-%d:\n", context.selection_start, context.selection_end)
		local selected_lines = {}
		for i = context.selection_start, context.selection_end do
			if i >= 1 and i <= #context.lines then
				table.insert(selected_lines, context.lines[i])
			else
				table.insert(selected_lines, "")
			end
		end
		context_info = context_info .. table.concat(selected_lines, "\n") .. "\n\n"
	else
		context_info = context_info .. string.format("Current line %d:\n", context.cursor_line)
		local current_line = ""
		if context.cursor_line >= 1 and context.cursor_line <= #context.lines then
			current_line = context.lines[context.cursor_line]
		end
		context_info = context_info .. current_line .. "\n\n"
	end

	context_info = context_info .. "Full file content (from editor buffer):\n" .. context.content

	local file = io.open(context_file, "w")
	if file then
		file:write(context_info)
		file:close()
	else
		vim.notify("Failed to create temporary file", vim.log.levels.ERROR)
		return
	end

	local escaped_input = user_input:gsub('"', '\\"')
	local cmd = string.format('cat "%s" | %s "%s"', context_file, config.claude_code_binary, escaped_input)

	local term_buf = create_terminal()

	local output_lines = {}

	local job_id = vim.fn.termopen(cmd, {
		on_stdout = function(_, data)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						table.insert(output_lines, line)
					end
				end
			end
		end,
		on_stderr = function(_, data)
			if data then
				for _, line in ipairs(data) do
					if line ~= "" then
						table.insert(output_lines, "ERROR: " .. line)
					end
				end
			end
		end,
		on_exit = function(_, code)
			vim.schedule(function()
				local cleanup = function()
					os.remove(context_file)
					os.remove(output_file)
				end
				
				if code == 0 then
					check_for_file_replacement(output_lines, context, term_buf, output_file, replacement_token, cleanup)
				else
					cleanup()
				end
			end)
		end,
	})

	vim.cmd('startinsert')
end

function M.run()
	local context = get_current_context()

	vim.ui.input({
		prompt = "Claude Code Input: ",
		default = "",
	}, function(input)
		if input and input ~= "" then
			run_claude_code(input, context)
		end
	end)
end

function M.setup(opts)
	config = vim.tbl_deep_extend("force", config, opts or {})
end

return M
