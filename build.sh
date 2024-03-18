#!/bin/bash

workspaceFolder=$(dirname "${BASH_SOURCE[0]}")

odin build "$workspaceFolder/src" -vet -out:${workspaceFolder}/out/abps -debug
