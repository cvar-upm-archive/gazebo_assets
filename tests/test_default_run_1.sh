#!/bin/bash

# Changing PX4 GPS origin
export PX4_HOME_LAT=28.143971
export PX4_HOME_LON=-16.503213
export PX4_HOME_ALT=0

# Set follow mode
export PX4_FOLLOW_MODE=1

# Set world
export PX4_SITL_WORLD="${AEROSTACK2_STACK}/simulation/gazebo_assets/worlds/frames.world"

# Set drone
export UAV_MODEL="iris"
export UAV_X=1.0
export UAV_Y=2.0
export UAV_Z=0.0
export UAV_YAW=1.0

${AEROSTACK2_STACK}/simulation/gazebo_assets/scripts/default_run.sh
