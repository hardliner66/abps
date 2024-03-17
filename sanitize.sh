#!/bin/bash

workspaceFolder=$(dirname "${BASH_SOURCE[0]}")

odin run "$workspaceFolder/src" -out:${workspaceFolder}/build/abps -debug -sanitize:memory
odin run "$workspaceFolder/src" -out:${workspaceFolder}/build/abps -debug -sanitize:address
