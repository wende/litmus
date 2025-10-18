       #!/bin/bash

       # Read JSON input
       input=$(cat)
       cwd=$(echo "$input" | jq -r '.workspace.current_dir')

       # Change to the working directory
       cd "$cwd" 2>/dev/null || cwd="$HOME"

       # Get current directory with ~ substitution
       current_dir="${cwd/#$HOME/~}"

       # Git information
       git_info=""
       if git rev-parse --git-dir > /dev/null 2>&1; then
           branch=$(git symbolic-ref --short HEAD 2>/dev/null || git rev-parse --short HEAD
       2>/dev/null)
           if [ -n "$branch" ]; then
               # Check if repo is dirty (skip optional locks to avoid blocking)
               if git --no-optional-locks diff --quiet 2>/dev/null && git --no-optional-locks
       diff --cached --quiet 2>/dev/null; then
                   # Clean repo
                   git_info=$(printf " \033[1;34mgit:(\033[0;31m%s\033[1;34m)\033[0m" "$branch")
               else
                   # Dirty repo
                   git_info=$(printf " \033[1;34mgit:(\033[0;31m%s\033[1;34m)\033[0m 
       \033[0;33m✗\033[0m" "$branch")
               fi
           fi
       fi

       # Print the status line (green arrow + cyan directory + git info)
       printf "\033[1;32m➜\033[0m  \033[0;36m%s\033[0m%s" "$current_dir" "$git_info"
