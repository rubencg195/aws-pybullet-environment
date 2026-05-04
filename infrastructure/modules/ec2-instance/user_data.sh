#!/bin/bash
# Legacy: bootstrap previously ran from cloud-init. The stack now uses a Packer-built golden AMI
# (see ../../packer/scripts/provision-al2023.sh). The EC2 module defaults to empty user_data.
# Keep this file only as a human reference or pass it explicitly via module user_data if needed.

exit 0
