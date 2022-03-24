#!/usr/bin/env bash

# TODO function variable into local variable
# TODO external MAYUSC internal minusc

function cleanup() {
	pkill -x px4  || true
	pkill gzclient
	pkill gzserver
}

function setup_gazebo() {
    [ -d "/usr/share/gazebo-7" ] && export GAZEBO_RESOURCE_PATH=$GAZEBO_RESOURCE_PATH:/usr/share/gazebo-7
    [ -d "/usr/share/gazebo-9" ] && export GAZEBO_RESOURCE_PATH=$GAZEBO_RESOURCE_PATH:/usr/share/gazebo-9
    [ -d "/usr/share/gazebo-11" ] && export GAZEBO_RESOURCE_PATH=$GAZEBO_RESOURCE_PATH:/usr/share/gazebo-11

    echo -e "GAZEBO_RESOURCE_PATH $GAZEBO_RESOURCE_PATH"
}

function parse_config_script() {
	pathfile=$1

	DIR_SCRIPT="${0%/*}"

	array=()
	while read line; do
		array+=($line)
	done < <(${DIR_SCRIPT}/parse_json.py $pathfile)

	local -n world=$2
	local -n drones_=$3

	world=${array[0]}
	drones_=("${array[@]:1}") #removed the 1st element

	if [[ ${#drones_[@]} -eq 0 ]]; then
		model=${UAV_MODEL:="iris"}
		x=${UAV_X:="0.0"}
		y=${UAV_Y:="0.0"}
		z=${UAV_Z:="0.0"}
		yaw=${UAV_YAW:="1.57"}
		drones_="${model}:${x}:${y}:${z}:${yaw}"
	fi
}

function parse_drone_config() {
	drone_config=$1

	local -n array=$2
	IFS_bak=$IFS
	IFS=":"
	for val in ${drone_config}; do
		array+=($val)
	done
	IFS=$IFS_bak
}

function run_gzserver() {
	world=$1
	world=$(eval echo $world)

	if [ "$world" == "none" ] && [[ -n "$PX4_SITL_WORLD" ]]; then
		world="$PX4_SITL_WORLD"
	fi

	# Check if world file exist, else empty world
	if [[ -f $world ]]; then
		world_path="$world"
	else
		world="none"
	fi

	if [ "$world" == "none" ]; then
		echo "empty world, setting empty.world as default"
		world_path="${src_path}/Tools/sitl_gazebo/worlds/empty.world"
	fi

	# To use gazebo_ros ROS2 plugins
	if [[ -n "$ROS_VERSION" ]] && [ "$ROS_VERSION" == "2" ]; then
		ros_args="-s libgazebo_ros_init.so -s libgazebo_ros_factory.so"
	else
		ros_args=""
	fi

	echo "Starting gazebo server"
	gzserver $verbose $world_path $ros_args &
	SIM_PID=$!
}

function run_gzclient() {
	px4_follow_mode=$1
	# Disable follow mode
	if [[ $px4_follow_mode -eq 1 ]]; then
		# FIXME: follow_mode not working
		follow_mode_="--gui-client-plugin libgazebo_user_camera_plugin.so"
	else
		follow_mode_=""
	fi

	# gzserver needs to be running to avoid a race. Since the launch
	# is putting it into the background we need to avoid it by backing off
	sleep 3
	# TODO: not working
	# while gz stats 2>&1 | grep -q "An instance of Gazebo is not running."; do
	# 	echo "gzserver not ready yet, trying again!"
	# 	sleep 1
	# done

	echo "Starting gazebo client"
	nice -n 20 gzclient $verbose $follow_mode_  # &  # TODO fails on headless
	GUI_PID=$!
}

function get_model_path() {
	model=$1

	# Check all paths in ${GAZEBO_MODEL_PATH} for specified model
	IFS_bak=$IFS
	IFS=":"
	for possible_model_path in ${GAZEBO_MODEL_PATH}; do
		if [ -z $possible_model_path ]; then
			continue
		fi
		# trim \r from path
		possible_model_path=$(echo $possible_model_path | tr -d '\r')
		if test -f "${possible_model_path}/${model}/${model}.sdf" ; then
			modelpath=$possible_model_path
			break
		fi
	done
	IFS=$IFS_bak

	echo $modelpath
}

function spawn_model() {
	N=$1
	model=$2
	x=$3
	y=$4
	z=$5
	Y=$6
	N=${N:=0}
	model=${model:=""}
	x=${x:=0.0}
	y=${y:=$((3*${N}))}
	z=${z:=0.0}
	Y=${Y:=1.57}
	

	if [ "$model" == "" ] || [ "$model" == "none" ]; then
		echo "empty model, setting iris as default"
		model="iris"
	fi

	modelpath="$(get_model_path ${model})"
	DIR_SCRIPT="${0%/*}"
	python3 ${DIR_SCRIPT}/jinja_gen.py ${modelpath}/${model}/${model}.sdf.jinja ${modelpath}/.. --mavlink_tcp_port $((4560+${N})) --mavlink_udp_port $((14560+${N})) --mavlink_id $((1+${N})) --gst_udp_port $((5600+${N})) --video_uri $((5600+${N})) --mavlink_cam_udp_port $((14530+${N})) --output-file /tmp/${model}_${N}.sdf

	gz model $verbose --spawn-file="/tmp/${model}_${N}.sdf" --model-name=${model}_${N} -x ${x} -y ${y} -z ${z} -Y ${Y} 2>&1
}

function run_sitl() {
	N=$1
	N=${N:=0}
	vehicle=$2
	vehicle=${vehicle:=""}

	NO_PXH=1
	# To disable user input
	if [[ -n "$NO_PXH" ]]; then
		no_pxh=-d
	else
		no_pxh=""
	fi

	# FIXME: VEHICLE --> IRIS
	vehicle=iris
	if [[ -n "$vehicle" ]]; then
		export PX4_SIM_MODEL=${vehicle}
	else
		export PX4_SIM_MODEL=iris
	fi

	working_dir="$build_path/tmp/sitl_${N}"
	mkdir -p "$working_dir"
	pushd "$working_dir" >/dev/null

	sitl_command="\"$sitl_bin\" -i $N $no_pxh \"$build_path\"/etc -s etc/init.d-posix/rcS -w $working_dir &"
	test_test___="\"$sitl_bin\" -i $N $no_pxh \"$build_path\"/etc -s etc/init.d-posix/rcS -w sitl_${MODEL}_${N} >out.log 2>err.log &"

	echo SITL COMMAND: $sitl_command
	eval $sitl_command

	popd >/dev/null
}

function spawn_drones() {
	drones=$1
	num_vehicles=${#drones[@]}

	n=0
	while [ $n -lt $num_vehicles ]; do
		local drone_array=()
		parse_drone_config ${drones[$n]} drone_array
		echo Spawn: ${drone_array[*]}

		spawn_model $n ${drone_array[*]}
		run_sitl $n $VEHICLE

		n=$(($n + 1))
	done
}

set -e

if [ "$#" -lt 4 ]; then
	echo "usage: $0 sitl_bin config_path src_path build_path"
	exit 1
fi

if [ ! -x "$(command -v gazebo)" ]; then
	echo "You need to have gazebo simulator installed!"
	exit 1
fi

sitl_bin="$1"
config_path="$2"
src_path="$3"
build_path="$4"

echo SITL ARGS

echo sitl_bin: $sitl_bin
echo config: $config_path
echo src_path: $src_path
echo build_path: $build_path

# Parse config file
declare world_path drones
parse_config_script $config_path world_path drones
echo drones: ${drones[*]}
echo world_path: $world_path

# Follow mode only available with one drone
if [[ ${#drones[@]} -gt 1 ]]; then
	follow_mode=""
else
	follow_mode=$PX4_FOLLOW_MODE
fi

# To disable user input
if [[ -n "$VERBOSE_SIM" ]]; then
	verbose="--verbose"
else
	verbose=""
fi

# kill process names that might stil
# be running from last time
echo "killing running instances"
trap "cleanup" SIGINT SIGTERM EXIT

sleep 1

source "${build_path}/build_gazebo/setup.sh"
source "$src_path/Tools/setup_gazebo.bash" "${src_path}" "${build_path}"
setup_gazebo

run_gzserver $world_path

# Do not exit on failure now from here on because we want the complete cleanup
set +e
spawn_drones $drones

if [[ -n "$HEADLESS" ]]; then
	echo "not running gazebo gui"
else
	run_gzclient $follow_mode
fi

kill -9 $SIM_PID
if [[ ! -n "$HEADLESS" ]]; then
	kill -9 $GUI_PID
fi
cleanup