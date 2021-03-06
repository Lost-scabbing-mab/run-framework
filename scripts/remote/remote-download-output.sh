#!/bin/bash


default="$(dirname $0)/../variables.sh"
variables_file=${VARIABLES_FILE:-$default}
echo "Using variables file = $variables_file" 
source $variables_file

if [ "$1" == "-h" -o "$1" == "--help" -o "$1" == "" ]; then
  echo "Usage: `basename $0` HOST KEY_FILE (default = ~/.ssh/ecs-key.pem)"
  exit 0
fi

prefix=$1
host=$2
keyfile=${3:-$HOME/.ssh/ecs-key.pem}
user=${4:-ec2-user}
remote_variables_file=${5:-/home/ec2-user/agief-project/variables/variables-ec2.sh}
port=${6:-22}

echo "Using prefix = " $prefix
echo "Using host = " $host
echo "Using keyfile = " $keyfile
echo "Using user = " $user
echo "Using remote_variables_file = " $remote_variables_file
echo "Using port = " $port

ssh -v -p $port -i $keyfile ${user}@${host} -o 'StrictHostKeyChecking no' prefix=$prefix VARIABLES_FILE=$remote_variables_file 'bash --login -s' <<'ENDSSH' 
	export VARIABLES_FILE=$VARIABLES_FILE
	source $VARIABLES_FILE

	download_folder=$AGI_RUN_HOME/output/$prefix
	echo "Calculated download-folder = " $download_folder

	# Sync with S3 only if the directory is empty or non-existent
	# ref: https://stackoverflow.com/q/20456666/
	if ! find "$download_folder" -mindepth 1 -print -quit | grep -q .; then
		# create folder if it doesn't exist
		mkdir -p $download_folder

		cmd="aws s3 cp s3://agief-project/experiment-output/$prefix/output $download_folder --recursive"

		echo $cmd >> remote-download-cmd.log
		eval $cmd >> remote-download-stdout.log 2>> remote-download-stderr.log
	fi

	# find zip file in download folder
	matching_files=( $(find $download_folder -maxdepth 1 -name '*.zip') )

	# ensure file exists before unzipping
	if [ ${matching_files[0]} ] && [ -f ${matching_files[0]} ]; then
		if [ `uname` == 'Darwin' ]; then
			unzip -o ${matching_files[0]} -d $download_folder
		else
			# unzip without .zip extension
			# ref: https://www.gnu.org/software/bash/manual/html_node/Shell-Parameter-Expansion.html
			unzip -o ${matching_files[0]%.*} -d $download_folder
		fi
	fi
ENDSSH

status=$?

if [ $status -ne 0 ]
then
	echo "ERROR: Could not complete remote download through ssh." >&2
	echo "	Error status = $status" >&2
	echo "	Exiting now." >&2
	exit $status
fi