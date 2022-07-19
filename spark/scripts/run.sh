#!/usr/bin/env bash

###################################################
#
# file: run.sh
#
# @Author:   Iacovos G. Kolokasis
# @Version:  20-01-2021 
# @email:    kolokasis@ics.forth.gr
#
# Scrpt to run the experiments
#
###################################################

. ./conf.sh
# Print error/usage script message
usage() {
  echo
  echo "Usage:"
  echo -n "      $0 [option ...] [-h]"
  echo
  echo "Options:"
  echo "      -n  Number of Runs"
  echo "      -t  Type of Storage Device (e.g SSD, NVMe, NVM)"
  echo "      -o  Output Path"
  echo "      -c  Enable TeraCache"
  echo "      -s  Enable serialization"
  echo "      -p  Enable perf tool"
  echo "      -f  Enable profiler tool"
  echo "      -a  Run experiments with high bench"
  echo "      -b  Run experiments with custom benchmark"
  echo "      -j  Enable metrics for JIT compiler"
  echo "      -h  Show usage"
  echo

  exit 1
}

##
# Description: 
#   Start Spark
##
start_spark() {
  ${SPARK_DIR}/sbin/start-all.sh >> ${BENCH_LOG} 2>&1
}

##
# Description: 
#   Stop Spark
##
stop_spark() {
  ${SPARK_DIR}/sbin/stop-all.sh >> ${BENCH_LOG} 2>&1
}

##
# Description: 
#   Stop perf monitor statistics with signal interupt (SIGINT)
#
##
stop_perf() {
  local perfPID=$(pgrep perf)

  # Kill all perf process
  for perf_id in ${perfPID}
  do
    kill -2 ${perf_id}
  done
}

##
# Description: 
#   Kill running background processes (jstat, serdes)
#
# Arguments:
#   $1 - Restart Spark
##
kill_back_process() {
  local jstatPID=$(pgrep jstat)
  local serdesPID=$(pgrep serdes)
  local perfPID=$(pgrep perf)

    # Kill all jstat process
    for jstat_pid in ${jstatPID}
    do
      kill -KILL ${jstat_pid}
    done

  # Kill all serdes process
  for serdes_pid in ${serdesPID}
  do
    kill -KILL ${serdes_pid}
  done

  # Kill all perf process
  for perf_id in ${perfPID}
  do
    kill -KILL ${perf_id}
  done

  if [[ $1 == "restart" ]]
  then
    stopSpark
    startSpark
  fi
}

##
# Description: 
#   Remove executors log files
##
cleanWorkDirs() {

  cd ${SPARK_DIR}/work

  for f in $(ls)
  do
    if [[ $f == "app-"* ]]
    then
      rm -rf ${f}
    fi
  done

  cd -
}

##
# Description: 
#   Console Message
#
# Arguments:
#   $1 - Device Name
#   $2 - Workload Name
#
##
printStartMsg() {
  echo
  echo "====================================================================="
  echo 
  echo "EXPERIMENTS"
  echo
  echo "      DEVICE   : $1"
  echo "      WORKLOAD : $2"
  echo
  echo -n "       Number of Partitions: "

}

##
# Description: 
#   Console Message
#
# Arguments:
#   $1 - End Time
#   $2 - Start Time
#
##
printEndMsg() {
  ELAPSEDTIME=$(($2 - $1))
  FORMATED="$(($ELAPSEDTIME / 3600))h:$(($ELAPSEDTIME % 3600 / 60))m:$(($ELAPSEDTIME % 60))s"  
  echo
  echo
  echo "    Benchmark Time Elapsed: $FORMATED"
  echo
  echo "====================================================================="
  echo
}

gen_config_files() {
  if [ $SERDES ]
  then
    cp ./configs/native/spark-defaults.conf ${SPARK_DIR}/conf
  else
    cp ./configs/teraheap/spark-defaults.conf ${SPARK_DIR}/conf
  fi
}

CUSTOM_BENCHMARK=false

# Check for the input arguments
while getopts ":n:t:o:cspkajfdbh" opt
do
  case "${opt}" in
    n)
      ITER=${OPTARG}
      ;;
    t)
      TYPE=${OPTARG}
      ;;
    o)
      OUTPUT_PATH=${OPTARG}
      ;;
    k)
      kill_back_process
      exit 1
      ;;
    c)
      TC=true
      ;;
    s)
      SERDES=true
      ;;
    p)
      PERF_TOOL=true
      ;;
    j)
      JIT=true
      ;;
    f)
      PROFILER=true
      ;;
    b)
      CUSTOM_BENCHMARK=true
      ;;
    h)
      usage
      ;;
    *)
      usage
      ;;
  esac
done

# Create directory for the results if do not exist
TIME=$(date +"%T-%d-%m-%Y")

OUT="${OUTPUT_PATH}_${TIME}"
mkdir -p ${OUT}

# Enable perf event
sudo sh -c 'echo -1 >/proc/sys/kernel/perf_event_paranoid'

gen_config_files

# Run each benchmark
for benchmark in "${BENCHMARKS[@]}"
do
  printStartMsg ${TYPE} ${benchmark}
  STARTTIME=$(date +%s)

  mkdir -p ${OUT}/${benchmark}

  # For every iteration
  for ((i=0; i<${ITER}; i++))
  do
    mkdir -p ${OUT}/${benchmark}/run${i}

    # For every configuration
    for ((j=0; j<${TOTAL_CONFS}; j++))
    do
      mkdir -p ${OUT}/${benchmark}/run${i}/conf${j}
      RUN_DIR="${OUT}/${benchmark}/run${i}/conf${j}"

      stop_spark

      # Set configuration
      if [ $SERDES ]
      then
        ./update_conf.sh -i $j -b ${CUSTOM_BENCHMARK}
      else
        ./update_conf_tc.sh -i $j -b ${CUSTOM_BENCHMARK}
      fi

      start_spark

      if [ -z "$JIT" ]
      then
        # Collect statics only for the garbage collector
        ./jstat.sh ${RUN_DIR} ${EXECUTORS} 0 &
      else
        # Collect statics for garbage collector and JIT
        ./jstat.sh ${RUN_DIR} ${EXECUTORS} 1 &
      fi

      if [ $PERF_TOOL ]
      then
        # Count total cache references, misses and pagefaults
        ./perf.sh ${RUN_DIR}/perf.txt ${EXECUTORS} &
      fi

      ./serdes.sh ${RUN_DIR}/serdes.txt ${EXECUTORS} &

      # Enable profiler
      if [ ${PROFILER} ]
      then
        ./profiler.sh ${RUN_DIR}/profile.svg ${EXECUTORS} &
      fi

      # Drop caches
      sudo sync && echo 3 | sudo tee /proc/sys/vm/drop_caches >> ${BENCH_LOG} 2>&1

      # Pmem stats before
      if [[ ${DEV_FMAP} == *pmem* ]]
      then
        sudo ipmctl show -performance >> ${RUN_DIR}/pmem_before.txt
      fi

      # System statistics start
      ~/system_util/start_statistics.sh -d ${RUN_DIR}

      if [ $CUSTOM_BENCHMARK == "true" ]
      then
        if [ $SERDES ]
        then
          ./custom_benchmarks.sh ${RUN_DIR} ${EXEC_CORES[$j]} ${HEAP[$j]} ${S_LEVEL[$j]}
        else
          ./custom_benchmarks.sh ${RUN_DIR} ${EXEC_CORES[$j]} ${TERACACHE[$j]} ${S_LEVEL[$j]}
        fi
      else
        # Run benchmark and save output to tmp_out.txt
        ${SPARK_BENCH_DIR}/${benchmark}/bin/run.sh \
          > ${RUN_DIR}/tmp_out.txt 2>&1
      fi            
      if [[ ${DEV_FMAP} == *pmem* ]]
      then
        # Pmem stats after
        sudo ipmctl show -performance >> ${RUN_DIR}/pmem_after.txt
      fi

      # System statistics stop
      ~/system_util/stop_statistics.sh -d ${RUN_DIR}

      if [ $SERDES ]
      then
        # Parse cpu and disk statistics results
        ~/system_util/extract-data.sh -r ${RUN_DIR} -d ${DEV_SHFL} -d ${DEV_FMAP} >> ${BENCH_LOG} 2>&1
      elif [ $TC ]
      then
        # Parse cpu and disk statistics results
        ~/system_util/extract-data.sh -r ${RUN_DIR} -d ${DEV_FMAP} -d ${DEV_SHFL}
      fi

      # Copy the confifuration to the directory with the results
      cp ./conf.sh ${RUN_DIR}/

      if [ $CUSTOM_BENCHMARK == "false" ]
      then
        # Save the total duration of the benchmark execution
        tail -n 1 ${SPARK_BENCH_DIR}/num/bench-report.dat >> ${RUN_DIR}/total_time.txt
      fi

      if [ $PERF_TOOL ]
      then
        # Stop perf monitor
        stop_perf
      fi

      # Parse results
      if [ $TC ]
      then
          TC_METRICS=$(ls -td ${SPARK_DIR}/work/* | head -n 1)
          cp ${TC_METRICS}/0/teraCache.txt ${RUN_DIR}/
          ./parse_results.sh -d ${RUN_DIR} -t
      elif [ $SERDES ]
      then
          ./parse_results.sh -d ${RUN_DIR} -s
      else
        ./parse_results.sh -d ${RUN_DIR}
      fi
    done
  done

  ENDTIME=$(date +%s)
  printEndMsg ${STARTTIME} ${ENDTIME}
done

exit
