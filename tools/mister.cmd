@echo off
setlocal
where python >nul 2>nul
if errorlevel 1 goto :use_py
python "%~dp0mister.py" %*
exit /b %errorlevel%

:use_py
where py >nul 2>nul
if errorlevel 1 (
  echo Python 3.10 or newer was not found. 1>&2
  exit /b 9009
)
py -3 "%~dp0mister.py" %*
exit /b %errorlevel%
