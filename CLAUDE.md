# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a Neovim plugin that integrates Claude Code with Neovim. The plugin allows users to:
- Press a keymap (`<leader>CC`) to open a prompt for user input
- Send the input along with the current file contents and cursor context to Claude Code
- Display Claude Code's output in a separate panel

## Architecture

This project is in early development with minimal structure:
- The plugin will integrate with Neovim's plugin system
- It will interface with the Claude Code CLI (documented at https://docs.anthropic.com/en/docs/claude-code/cli-usage)
- The core functionality involves capturing editor context (file contents, cursor position/selection) and passing it to Claude Code

## Key Features to Implement

- Keymap binding for `<leader>CC` to trigger the Claude Code interaction
- User input prompt system
- Context extraction from Neovim (current file, cursor position, text selection)
- Communication with Claude Code CLI
- Output display panel
- Configuration option for Claude Code binary path

## Development Notes

This is a Neovim plugin project that will likely use Lua for implementation (standard for modern Neovim plugins). The plugin structure should follow Neovim plugin conventions with appropriate directory structure for lua files, plugin definitions, and documentation.