#!/usr/bin/env bash

###################################################
#
# file: dev_setup.sh
#
# @Author:   Iacovos G. Kolokasis
# @Version:  19-09-2021
# @email:    kolokasis@ics.forth.gr
#
# Prepare the devices for the experiments
#
###################################################

# Check if the last command executed succesfully
#
# if executed succesfully, print SUCCEED
# if executed with failures, print FAIL and exit
check () {
    if [ $1 -ne 0 ]
    then
        echo -e "  $2 \e[40G [\e[31;1mFAIL\e[0m]"
        exit
    else
        echo -e "  $2 \e[40G [\e[32;1mSUCCED\e[0m]"
    fi
}

# Print error/usage script message
usage() {
    echo
    echo "Usage:"
    echo -n "      $0 [option ...] [-k][-h]"
    echo
    echo "Options:"
    echo "      -t  Run experiments with teraCache"
    echo "      -f  Run experiments with fastmap"
    echo "      -s  File size for TeraCache"
    echo "      -d  List for devices. First device for TeraCache and second for Suffle"
    echo "      -u  Unmount all devices"
    echo "      -h  Show usage"
    echo

    exit 1
}

destroy_th() {
	if [ "$1" ]
	then
		sudo umount "${MNT_SHFL}"
		# Check if the command executed succesfully
		retValue=$?
		message="Unmount ${DEVICES[1]}" 
		check ${retValue} "${message}"

		rm -rf "${MNT_FMAP}"/file.txt
		# Check if the command executed succesfully
		retValue=$?
		message="Remove TeraHeap H2 backed-file" 
		check ${retValue} "${message}"
	else
		rm -rf "${MNT_SHFL}"/file.txt
		# Check if the command executed succesfully
		retValue=$?
		message="Remove TeraHeap H2 backed-file" 
		check ${retValue} "${message}"
		
		sudo umount /mnt/spark
		# Check if the command executed succesfully
		retValue=$?
		message="Unmount ${DEVICES[0]}" 
		check ${retValue} "${message}"
	fi
}

destroy_ser() {
	sudo umount "${MNT_SHFL}"
	# Check if the command executed succesfully
	retValue=$?
	message="Unmount $DEVICE_SHFL" 
	check ${retValue} "${message}"
}
    
# Check for the input arguments
while getopts ":s:d:tfuh" opt
do
    case "${opt}" in
		t)
			TH=true
			;;
		s)
			TH_FILE_SZ=${OPTARG}
			;;
		d)
			DEVICE_SHFL=${OPTARG}
			;;
		u)
			DESTROY=true
			;;
    h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

# Unmount TeraCache device
if [ $DESTROY ]
then
	if [ $TH ]
	then
		destroy_th $FASTMAP
	else
		destroy_ser
	fi
	exit
fi

# Setup Device 
if ! mountpoint -q /mnt/datasets
then
	sudo mount /dev/sdb /mnt/datasets
	sudo chown kolokasis /mnt/datasets
fi

# Setup TeraCache device
if [ $TH ]
then
		if ! mountpoint -q /mnt/spark
		then
			sudo mount /dev/${DEVICE_SHFL} /mnt/spark
			# Check if the command executed succesfully
			retValue=$?
			message="Mount ${DEVICE_SHFL} for shuffle and TeraCache" 
			check ${retValue} "${message}"

      sudo chown "$(whoami)" /mnt/spark
			# Check if the command executed succesfully
			retValue=$?
			message="Change ownerships /mnt/spark" 
			check ${retValue} "${message}"
		fi

		cd /mnt/spark || exit

		# if the file does not exist then create it
		if [ ! -f file.txt ]
		then
			fallocate -l ${TH_FILE_SZ}G file.txt
			# Check if the command executed succesfully
			retValue=$?
			message="Create ${TH_FILE_SZ}G file for TeraCache" 
			check ${retValue} "${message}"
		else
			rm file.txt
			# Check if the command executed succesfully
			retValue=$?
			message="Remove ${TH_FILE_SZ}G file" 
			check ${retValue} "${message}"
			
			fallocate -l ${TH_FILE_SZ}G file.txt
			# Check if the command executed succesfully
			retValue=$?
			message="Create ${TH_FILE_SZ}G file for TeraCache" 
			check ${retValue} "${message}"
		fi
		cd -
	fi
else
	if mountpoint -q /mnt/spark
	then
		exit
	fi
	sudo mount /dev/${DEVICE_SHFL} /mnt/spark
	# Check if the command executed succesfully
	retValue=$?
	message="Mount ${DEVICE_SHFL} /mnt/spark" 
	check ${retValue} "${message}"
		
	sudo chown kolokasis /mnt/spark
	# Check if the command executed succesfully
	retValue=$?
	message="Change ownerships /mnt/spark" 
	check ${retValue} "${message}"
fi
exit
