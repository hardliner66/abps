#!/bin/bash

workspaceFolder=$(dirname "${BASH_SOURCE[0]}")

odin run "$workspaceFolder/src" -out:${workspaceFolder}/build/abps -debug
