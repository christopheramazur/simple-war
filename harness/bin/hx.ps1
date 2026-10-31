#!/usr/bin/env pwsh
# hx shim for PowerShell.
& uv run --project (Join-Path $PSScriptRoot '..') --quiet hx @args
exit $LASTEXITCODE
