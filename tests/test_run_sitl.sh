#!/bin/bash

AEROSTACK_PROJECT="$(dirname ${PWD})/scripts"

SCRIPT_PATH="${AEROSTACK2_STACK}/simulation/gazebo_assets/scripts"
PX4_FOLDER="${AEROSTACK2_WORKSPACE}/src/thirdparty/PX4-Autopilot"

WORLD_PATH="${AEROSTACK_PROJECT}/configs/gazebo/worlds/planta.world"

# export VEHICLE="iris"

MODEL_FOLDER="${AEROSTACK_PROJECT}/configs/gazebo/models"

# TODO
if [[ -e FILE ]]; then
	sed -i -r "s/(<namespace>).+[[:alnum:]].+(<\/namespace>)/\1$AEROSTACK2_SIMULATION_DRONE_ID\2/" "$MODEL_FOLDER/$UAV_MODEL/$UAV_MODEL.sdf"
fi

# export HEADLESS=1
export PX4_NO_FOLLOW_MODE=1

export PX4_HOME_LAT=28.143993735855286
export PX4_HOME_LON=-16.50324122923412
export PX4_HOME_ALT=0

(cd $PX4_FOLDER; DONT_RUN=1 make px4_sitl_rtps gazebo)
export ROS_PACKAGE_PATH=$ROS_PACKAGE_PATH:$PX4_FOLDER:$PX4_FOLDER/Tools/sitl_gazebo
export GAZEBO_MODEL_PATH=$GAZEBO_MODEL_PATH:$MODEL_FOLDER

export UAV_MODEL="iris"
export UAV_X=-5.0
export UAV_Y=0.0
export UAV_Z=0.0
export UAV_YAW=1.57
$SCRIPT_PATH/run_sitl.sh "$PX4_FOLDER/build/px4_sitl_rtps/bin/px4" 'config.json' $PX4_FOLDER $PX4_FOLDER/build/px4_sitl_rtps
