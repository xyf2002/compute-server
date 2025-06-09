# compute-server

This repository contains scripts used to configure compute nodes.

## Kernel build

`scripts/build_kernel.sh` clones and compiles a Linux kernel and installs it on the node. The script is invoked automatically from `profile.py` via the environment variable `PROFILE_CONF_COMMAND_KERNEL`. Extra arguments can be supplied through `PROFILE_CONF_COMMAND_KERNEL_ARGS` which correspond to the optional `kernelArgs` profile parameter.

