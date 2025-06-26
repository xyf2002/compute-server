#!/bin/bash
  sudo apt update 
  sudo apt-get install -yqq libsctp-dev lksctp-tools  zlib1g-dev
  sudo modprobe sctp