#!/bin/bash

workspaceFolder=$(dirname "${BASH_SOURCE[0]}")

odin run "$workspaceFolder/src" -out:${workspaceFolder}/out/abps -debug -sanitize:memory
odin run "$workspaceFolder/src" -out:${workspaceFolder}/out/abps -debug -sanitize:address
