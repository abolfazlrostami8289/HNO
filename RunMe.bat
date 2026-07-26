@echo off
REM ---------------------------------------------------------------------------
REM  Hamyar Nejat installer entry point.
REM
REM  IMPORTANT: elevation (-Verb RunAs) has been REMOVED deliberately.
REM  The installer now installs Python per-user to a local folder, creates a
REM  local venv, and uses portable Ollama in place. None of that needs
REM  administrator rights.
REM
REM  Running elevated would resolve %USERPROFILE% and the Desktop folder to the
REM  ADMINISTRATOR's profile, so the shortcut would land on the wrong desktop
REM  and the end user would see nothing after a "successful" install.
REM
REM  Usage:
REM    RunMe.bat            graphical installer
REM    RunMe.bat -Silent    unattended, console output, exit code 0/1
REM ---------------------------------------------------------------------------
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0install.ps1" %*
