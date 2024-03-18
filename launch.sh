#!/bin/bash

workspaceFolder=$(dirname "${BASH_SOURCE[0]}")

odin run "$workspaceFolder/src" -vet -out:${workspaceFolder}/out/abps -debug
