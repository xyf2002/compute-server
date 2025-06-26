#!/bin/bash

# Extract numeric ID from hostname, e.g., node0 → 0
C_ID=$(hostname | grep -o '[0-9]\+')

# Run the main binary with extracted c_id
/local/repository/scripts/slotcheckerservice "$C_ID"
