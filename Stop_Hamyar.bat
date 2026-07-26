@echo off
REM ---------------------------------------------------------------------------
REM  Stop Hamyar Nejat - closes Streamlit and Ollama, frees model memory.
REM  Usage:
REM    Stop_Hamyar.bat            normal shutdown
REM    Stop_Hamyar.bat -Force     also stop a pre-existing Ollama server
REM    Stop_Hamyar.bat -All       sweep for stray processes by executable path
REM ---------------------------------------------------------------------------
PowerShell -NoProfile -ExecutionPolicy Bypass -File "%~dp0stop.ps1" %*
